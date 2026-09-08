import Foundation
import SwiftData

@main
struct LegacyStore {
    @MainActor static func main() throws {
        let schema = Schema([TxRecord.self, CategoryModel.self, AccountModel.self, BudgetModel.self, SubscriptionModel.self])
        let configuration = ModelConfiguration(schema: schema, url: URL(fileURLWithPath: CommandLine.arguments[1]), cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let account = AccountModel(name: "测试账户", icon: "", type: .bank, initialBalance: 500)
        context.insert(account)
        let parent = CategoryModel(name: "餐饮", icon: "", type: .expense, sortOrder: 0)
        context.insert(parent)
        context.insert(CategoryModel(name: "早餐", icon: "", type: .expense, sortOrder: 0, parent: parent))
        for (amount, type, sub) in [(60.0, TransactionType.expense, "早餐"), (40.0, .expense, ""), (1000.0, .income, "")] {
            let record = TxRecord(amount: amount, type: type, categoryName: type == .expense ? "餐饮" : "工资", categoryIcon: "", subcategoryName: sub, note: "旧版保留")
            record.account = account
            context.insert(record)
        }
        context.insert(BudgetModel(amount: 500))
        let subscription = SubscriptionModel(name: "旧订阅", cycle: .monthly, amount: 30, firstAmount: 30, startDate: .now, categoryName: "其他", categoryIcon: "")
        subscription.account = account
        context.insert(subscription)
        try context.save()
        print("PASS: legacy 1.0 store written with transactions, relationships, budget and subscription")
    }
}
