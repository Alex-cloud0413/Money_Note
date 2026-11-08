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
            precondition(records.contains { $0.note == "audit-trash" && $0.isTrashed })
            precondition(cats.contains { $0.name == "餐食" && $0.matches("餐饮") && $0.archived == true })
            print("PASS: renamed categories, monthly budgets and recoverable deletion survive restart")
            return
        }
        let today = Calendar.current.startOfDay(for: .now)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let future = Calendar.current.date(byAdding: .month, value: 2, to: today)!
        let parent = CategoryModel(name: "餐饮", icon: "fork.knife", type: .expense, sortOrder: 0)
        context.insert(parent)
        let child = CategoryModel(name: "外卖", icon: "fork.knife", type: .expense, sortOrder: 0, parent: parent)
        context.insert(child)
        let original = TxRecord(amount: 100, type: .expense, categoryName: "餐饮", categoryIcon: "", subcategoryName: "外卖", note: "audit-rename", date: today)
        context.insert(original)
        let income = TxRecord(amount: 50, type: .income, categoryName: "工资", categoryIcon: "", date: today)
        context.insert(income)
        let planned = TxRecord(amount: 500, type: .expense, categoryName: "餐饮", categoryIcon: "", date: tomorrow)
        context.insert(planned)
        let recurring = BudgetModel(categoryName: "餐饮", amount: 500)
        context.insert(recurring)
        let sub = SubscriptionModel(name: "Audit Subscription", cycle: .yearly, amount: 100, firstAmount: 89.99, startDate: today, categoryName: "餐饮", categoryIcon: "", subcategoryName: "外卖")
        context.insert(sub)
        try context.save()
        precondition([original, income].reduce(0) { $0 + $1.signedAmount } == -50)
        precondition(LedgerAnalytics.records([original, income, planned], ledger: "life", month: today).count == 3)
        print("PASS: mixed income/expense is net flow and future entries remain explicit monthly plans")
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
        parent.archived = true
        precondition(child.isArchived)
        original.deletedAt = .now
        precondition(!LedgerAnalytics.records([original], ledger: "life", month: today).contains { $0 === original })
        original.deletedAt = nil
        precondition(original.subcategoryName == "送餐")
        let trash = TxRecord(amount: 1, type: .expense, categoryName: "餐食", categoryIcon: "", note: "audit-trash", date: today)
        trash.deletedAt = .now; context.insert(trash)
        print("PASS: category archive and soft delete preserve and restore transaction details")
        try DataMaintenance.migrateLegacyBudgets(context, to: today)
        precondition(recurring.monthKey == SubscriptionEngine.monthKey(today))
        precondition(BudgetRules.effective([recurring], ledger: "life", month: today).first?.amount == 500)
        precondition(BudgetRules.effective([recurring], ledger: "life", month: future).isEmpty)
        let retainedLegacy = BudgetModel(categoryName: "餐食", amount: 450)
        context.insert(retainedLegacy)
        try DataMaintenance.migrateLegacyBudgets(context, to: today)
        precondition(retainedLegacy.monthKey == nil)
        precondition(BudgetRules.effective([recurring, retainedLegacy], ledger: "life", month: today).first?.amount == 500)
        let futureBudget = BudgetModel(categoryName: "餐食", amount: 700)
        futureBudget.monthKey = SubscriptionEngine.monthKey(future); context.insert(futureBudget)
        precondition(BudgetRules.effective([recurring, futureBudget], ledger: "life", month: today).first?.amount == 500)
        precondition(BudgetRules.effective([recurring, futureBudget], ledger: "life", month: future).first?.amount == 700)
        print("PASS: every month has an independent budget and legacy repeating rules localize once")
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
        try dailyAllocation(context)
        checkDateRange()
        precondition(Calc.evaluate("12+3×4") == 24)
        precondition(Calc.evaluate("1÷0") == nil)
        precondition(Calc.evaluate("abc") == nil)
        precondition(CSVExport.escape("=1+1") == "\"'=1+1\"")
        precondition(CSVExport.escape("a,\"b") == "\"a,\"\"b\"")
        print("PASS: calculator invalid arithmetic and CSV escaping")
        try context.save()
    }
    @MainActor private static func dailyAllocation(_ context: ModelContext) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let leapStart = calendar.date(from: DateComponents(year: 2024, month: 1, day: 31))!
        let count = AllocationUnit.day.count(start: leapStart, months: 3, calendar: calendar)
        precondition(count == 90)
        let cents = (0..<count).map { Int((AllocationUnit.share(total: 100.01, count: count, index: $0) * 100).rounded()) }
        precondition(cents.reduce(0, +) == 10_001 && cents.max()! - cents.min()! == 1)
        precondition(AllocationUnit.day.date(at: count, start: leapStart, calendar: calendar)
                     == calendar.date(from: DateComponents(year: 2024, month: 4, day: 30)))

        let local = Calendar.current
        let today = local.startOfDay(for: .now)
        let start = local.date(byAdding: .day, value: -15, to: today)!
        let end = local.date(byAdding: .month, value: 1, to: start)!
        let quote = FXQuote(currency: .USD, rate: 7.12, timestamp: start, historical: true)
        let foreign = ForeignAmount(original: 30.01, quote: quote)
        let daily = SubscriptionModel(name: "Daily", cycle: .monthly, amount: quote.converted(30.01),
                                      firstAmount: quote.converted(10.01), startDate: start,
                                      categoryName: "其他", categoryIcon: "")
        daily.allocation = .day
        daily.foreignAmount = foreign
        daily.foreignFirstAmount = 10.01
        context.insert(daily)
        func records() throws -> [TxRecord] {
            try context.fetch(FetchDescriptor<TxRecord>()).filter { $0.subscriptionUID == daily.uid }
        }
        try SubscriptionEngine.sync(context, upTo: end, only: daily.uid)
        let first = try records().filter { $0.date < end }
        precondition(first.count == AllocationUnit.day.count(start: start, months: 1))
        precondition(abs(first.reduce(0) { $0 + $1.amount } - quote.converted(10.01)) < 0.00001)
        precondition(abs(first.reduce(0) { $0 + ($1.foreignAmount?.original ?? 0) } - 10.01) < 0.00001)
        precondition(first.allSatisfy { $0.allocation == .day && $0.foreignAmount?.quote == quote })
        let initialCount = try records().count
        first[0].deletedAt = .now
        try SubscriptionEngine.sync(context, upTo: end, only: daily.uid)
        let afterSync = try records()
        precondition(afterSync.count == initialCount && afterSync.filter(\.isTrashed).count == 1)
        daily.isActive = false
        try SubscriptionEngine.sync(context, only: daily.uid)
        let stopped = try records()
        precondition(stopped.allSatisfy { $0.date <= today } && !stopped.isEmpty)
        daily.isActive = true
        daily.allocation = .month
        try SubscriptionEngine.sync(context, upTo: end, rewriteAmounts: true, only: daily.uid)
        let monthly = try records()
        precondition(monthly.count == 2)
        precondition(monthly.allSatisfy { $0.allocation == .month && $0.subscriptionMonthKey.count == 7 })
        precondition(monthly.contains { abs($0.amount - quote.converted(10.01)) < 0.00001 })
        print("PASS: calendar days, leap month, cent conservation, first-cycle FX, deletion, stopping and mode switch")
    }

    private static func checkDateRange() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 13))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 7))!
        let lastMoment = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 23, minute: 59))!
        let range = CSVExport.days(from: start, through: end, calendar: calendar)!
        precondition(range.contains(calendar.startOfDay(for: start)) && range.contains(lastMoment))
        precondition(!range.contains(range.upperBound))
        precondition(CSVExport.days(from: end, through: start, calendar: calendar) == nil)
        let oneDay = CSVExport.days(from: end, through: end, calendar: calendar)!
        precondition(oneDay.upperBound.timeIntervalSince(oneDay.lowerBound) == 25 * 3600)
        print("PASS: CSV includes both dates across months and DST, rejects reversed ranges, supports a single day")
    }

}
