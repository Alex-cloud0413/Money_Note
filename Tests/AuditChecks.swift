import Foundation
import SwiftData

@main
struct AuditChecks {
    @MainActor static func main() throws {
        let schema = Schema([TxRecord.self, CategoryModel.self, AccountModel.self, BudgetModel.self, SubscriptionModel.self, LedgerModel.self])
        let configuration = ModelConfiguration(schema: schema, url: URL(fileURLWithPath: CommandLine.arguments[1]), cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        if CommandLine.arguments.contains("--reopen") {
            let records = try context.fetch(FetchDescriptor<TxRecord>())
            let cats = try context.fetch(FetchDescriptor<CategoryModel>())
            let accounts = try context.fetch(FetchDescriptor<AccountModel>())
            precondition(records.contains { $0.note == "audit-trash" && $0.isTrashed && $0.account?.name == "Audit Account" })
            precondition(cats.contains { $0.name == "餐食" && $0.matches("餐饮") && $0.archived == true })
            precondition(accounts.contains { $0.name == "Audit Account" && $0.isArchived })
            print("PASS: renamed categories, archived accounts and recoverable deletion survive restart")
            return
        }
        let today = Calendar.current.startOfDay(for: .now)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let future = Calendar.current.date(byAdding: .month, value: 2, to: today)!
        let account = AccountModel(name: "Audit Account", icon: "creditcard", type: .bank, initialBalance: 1000)
        context.insert(account)
        let parent = CategoryModel(name: "餐饮", icon: "fork.knife", type: .expense, sortOrder: 0)
        context.insert(parent)
        let child = CategoryModel(name: "外卖", icon: "fork.knife", type: .expense, sortOrder: 0, parent: parent)
        context.insert(child)
        let original = TxRecord(amount: 100, type: .expense, categoryName: "餐饮", categoryIcon: "", subcategoryName: "外卖", note: "audit-rename", date: today)
        original.account = account; context.insert(original)
        let income = TxRecord(amount: 50, type: .income, categoryName: "工资", categoryIcon: "", date: today)
        income.account = account; context.insert(income)
        let planned = TxRecord(amount: 500, type: .expense, categoryName: "餐饮", categoryIcon: "", date: tomorrow)
        planned.account = account; context.insert(planned)
        let recurring = BudgetModel(categoryName: "餐饮", amount: 500)
        context.insert(recurring)
        let sub = SubscriptionModel(name: "Audit Subscription", cycle: .yearly, amount: 100, firstAmount: 89.99, startDate: today, categoryName: "餐饮", categoryIcon: "", subcategoryName: "外卖")
        sub.account = account; context.insert(sub)
        try context.save()
        precondition(account.balance(asOf: today) == 950)
        precondition(account.balance(asOf: tomorrow) == 450)
        precondition([original, income].reduce(0) { $0 + $1.signedAmount } == -50)
        print("PASS: mixed income/expense is net flow; future entries excluded from current account balance")
        try CategoryOperations.update(parent, name: "餐食", icon: "fork.knife", in: context)
        try CategoryOperations.update(child, name: "送餐", icon: "bag", in: context)
        precondition(original.categoryName == "餐食" && original.subcategoryName == "送餐")
        precondition(sub.categoryName == "餐食" && sub.subcategoryName == "送餐")
        precondition(recurring.categoryName == "餐食")
        precondition(CategoryOperations.resolvedPins("餐饮\n餐食", categories: [parent]) == ["餐食"])
        let delayed = TxRecord(amount: 10, type: .expense, categoryName: "餐饮", categoryIcon: "", subcategoryName: "外卖", note: "late import", date: today)
        context.insert(delayed); try CategoryOperations.reconcile(in: context)
        precondition(delayed.categoryName == "餐食" && delayed.subcategoryName == "送餐")
        do { try CategoryOperations.validate("餐饮", category: nil, parent: nil, type: .expense, in: context); preconditionFailure("Alias collision should fail") }
        catch CategoryOperations.EditError.duplicate { }
        print("PASS: parent/child renames update records, subscriptions, budgets, and delayed legacy imports; alias collisions rejected")
        parent.archived = true; account.archived = true
        precondition(child.isArchived && original.account === account)
        original.deletedAt = .now
        precondition(!LedgerAnalytics.records([original], ledger: "life", month: today).contains { $0 === original })
        precondition(account.balance(asOf: today) == 1050)
        original.deletedAt = nil
        precondition(account.balance(asOf: today) == 950 && original.account === account && original.subcategoryName == "送餐")
        let trash = TxRecord(amount: 1, type: .expense, categoryName: "餐食", categoryIcon: "", note: "audit-trash", date: today)
        trash.account = account; trash.deletedAt = .now; context.insert(trash)
        print("PASS: archive retains relationships; soft delete excludes balances/analytics and restores exactly")
        let override = BudgetModel(categoryName: "餐食", amount: 700)
        override.monthKey = SubscriptionEngine.monthKey(today); context.insert(override)
        precondition(BudgetRules.effective([recurring, override], ledger: "life", month: today).first?.amount == 700)
        precondition(BudgetRules.effective([recurring, override], ledger: "life", month: future).first?.amount == 500)
        print("PASS: monthly budget override leaves recurring rule and other months unchanged")
        let endFirstCycle = Calendar.current.date(byAdding: .month, value: 11, to: today)!
        try SubscriptionEngine.sync(context, upTo: endFirstCycle)
        var generated = try context.fetch(FetchDescriptor<TxRecord>()).filter { $0.subscriptionUID == sub.uid }
        precondition(generated.count == 12)
        precondition(abs(generated.reduce(0) { $0 + $1.amount } - 89.99) < 0.00001)
        generated[0].deletedAt = .now
        try SubscriptionEngine.sync(context, upTo: endFirstCycle)
        generated = try context.fetch(FetchDescriptor<TxRecord>()).filter { $0.subscriptionUID == sub.uid }
        precondition(generated.count == 12 && generated.filter(\.isTrashed).count == 1)
        let savedAmount = generated[0].amount
        sub.firstAmount = 189
        try SubscriptionEngine.sync(context, upTo: endFirstCycle)
        precondition(generated[0].amount == savedAmount)
        try SubscriptionEngine.sync(context, upTo: endFirstCycle, rewriteAmounts: true)
        precondition(abs(generated.reduce(0) { $0 + $1.amount } - 189) < 0.00001)
        print("PASS: startup preserves existing subscription amounts; explicit editor recalculation applies requested changes")
        sub.isActive = false
        try SubscriptionEngine.sync(context)
        let kept = try context.fetch(FetchDescriptor<TxRecord>()).filter { $0.subscriptionUID == sub.uid }
        precondition(kept.count == 1)
        print("PASS: annual subscription cents sum exactly, sync is idempotent, and stop retains history while removing future plans")
        precondition(Calc.evaluate("12+3×4") == 24)
        precondition(Calc.evaluate("1÷0") == nil)
        precondition(Calc.evaluate("abc") == nil)
        precondition(CSVExport.escape("=1+1") == "\"'=1+1\"")
        precondition(CSVExport.escape("a,\"b") == "\"a,\"\"b\"")
        print("PASS: calculator invalid arithmetic and CSV escaping")
        try context.save()
    }
}
