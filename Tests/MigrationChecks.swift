import Foundation
import SwiftData

@main
struct MigrationChecks {
    @MainActor static func main() throws {
        let schema = Schema([TxRecord.self, CategoryModel.self, AccountModel.self, BudgetModel.self, SubscriptionModel.self, LedgerModel.self])
        let configuration = ModelConfiguration(schema: schema, url: URL(fileURLWithPath: CommandLine.arguments[1]), cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let records = try context.fetch(FetchDescriptor<TxRecord>())
        if CommandLine.arguments.contains("--reopen") {
            precondition(records.filter { $0.note == "旧版保留" }.count == 3)
            precondition(records.filter { $0.note == "事业测试" && $0.ledgerKey == "work" }.count == 1)
            let count = try context.fetchCount(FetchDescriptor<LedgerModel>())
            precondition(count == 1)
            print("PASS: migrated and new records survive process restart")
            return
        }
        precondition(records.count == 3)
        precondition(records.allSatisfy { $0.ledgerKey == "life" && $0.bookID == nil })
        precondition(records.allSatisfy { $0.account?.name == "测试账户" && $0.note == "旧版保留" })
        let accounts = try context.fetch(FetchDescriptor<AccountModel>())
        precondition(abs(accounts[0].balance - 1400) < 0.001)
        let categories = try context.fetch(FetchDescriptor<CategoryModel>())
        precondition(categories.first { $0.name == "早餐" }?.parent?.name == "餐饮")
        let budgets = try context.fetch(FetchDescriptor<BudgetModel>())
        let subs = try context.fetch(FetchDescriptor<SubscriptionModel>())
        precondition(budgets[0].ledgerKey == "life" && budgets[0].amount == 500)
        precondition(subs[0].ledgerKey == "life" && subs[0].account?.name == "测试账户")
        print("PASS: real 1.0 to 1.1 lightweight migration preserves all old fields and relationships")

        let work = TxRecord(amount: 200, type: .expense, categoryName: "餐饮", categoryIcon: "", subcategoryName: "早餐", note: "事业测试")
        work.ledgerKey = "work"; work.account = accounts[0]; context.insert(work)
        let oldMonth = TxRecord(amount: 999, type: .expense, categoryName: "餐饮", categoryIcon: "", date: Calendar.current.date(byAdding: .month, value: -1, to: .now)!)
        context.insert(oldMonth)
        context.insert(BudgetModel(amount: 800, ledgerKey: "work"))
        context.insert(LedgerModel(name: "旅行账本"))
        try context.save()
        let all = try context.fetch(FetchDescriptor<TxRecord>())
        let life = LedgerAnalytics.records(all, ledger: "life", month: .now, type: .expense)
        let business = LedgerAnalytics.records(all, ledger: "work", month: .now, type: .expense)
        precondition(life.count == 2 && business.count == 1)
        let root = LedgerAnalytics.categories(life)
        let children = LedgerAnalytics.categories(life, children: true)
        precondition(root.count == 1 && root[0].amount == 100)
        precondition(children.count == 2 && abs(children.map(\.share).reduce(0,+) - 1) < 0.000001)
        precondition(children.first { $0.name == "早餐" }?.share == 0.6)
        precondition(children.first { $0.name == "未分子类" }?.share == 0.4)
        precondition(LedgerAnalytics.categories([]).isEmpty)
        print("PASS: ledger, month and type isolation; subcategory percentages include unassigned records")

        subs[0].ledgerKey = "work"
        SubscriptionEngine.sync(context)
        let generated = try context.fetch(FetchDescriptor<TxRecord>()).filter { $0.subscriptionUID == subs[0].uid }
        precondition(generated.count == 1 && generated[0].ledgerKey == "work")
        SubscriptionEngine.sync(context)
        let synced = try context.fetch(FetchDescriptor<TxRecord>())
        precondition(synced.filter { $0.subscriptionUID == subs[0].uid }.count == 1)
        subs[0].ledgerKey = "life"; SubscriptionEngine.sync(context)
        precondition(generated[0].ledgerKey == "life")
        print("PASS: subscription records inherit the ledger, stay idempotent and follow subscription edits")

        for total in [0.06, 0.09, 0.29, 10.0, 100.0, 1000.99] {
            for periods in 2...60 {
                let plan = InstallmentPlan.amounts(total: total, periods: periods)
                if Int((total * 100).rounded()) >= periods {
                    precondition(plan.count == periods && plan.allSatisfy { $0 > 0 })
                    precondition(abs(plan.reduce(0,+) - total) < 0.00001)
                } else { precondition(plan.isEmpty) }
            }
        }
        print("PASS: 354 installment boundary cases preserve cents without zero or negative installments")
        try context.save()
    }
}
