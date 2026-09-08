#if DEBUG
import Foundation
import SwiftData

/// Opt-in, in-memory fixtures only. Never opens or modifies the user's persistent store.
@MainActor
enum DemoData {
    static func populate(_ context: ModelContext) {
        CategoryModel.seedDefaultsIfNeeded(context)
        AccountModel.seedDefaultsIfNeeded(context)
        let account = (try? context.fetch(FetchDescriptor<AccountModel>()))?.first
        let samples: [(Double, TransactionType, String, String, String, String, Int)] = [
            (36, .expense, "餐饮", "早餐", "巷口的早餐", "life", 0),
            (128, .expense, "餐饮", "聚餐", "和朋友吃饭", "life", 1),
            (24, .expense, "交通", "地铁", "通勤", "life", 1),
            (58, .expense, "餐饮", "外卖", "午餐", "life", 2),
            (96, .expense, "购物", "日用品", "补一些生活用品", "life", 2),
            (48, .expense, "餐饮", "", "周末咖啡", "life", 3),
            (12000, .income, "工资", "", "九月工资", "life", 4),
            (299, .expense, "学习", "书籍", "专业书籍", "work", 1),
            (168, .expense, "其他", "工具", "创作工具", "work", 2),
            (2600, .income, "兼职", "", "项目收入", "work", 3)
        ]
        for (amount, type, category, subcategory, note, ledger, days) in samples {
            let tx = TxRecord(amount: amount, type: type, categoryName: category, categoryIcon: "",
                              subcategoryName: subcategory, note: note,
                              date: Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now)
            tx.ledgerKey = ledger
            tx.account = account
            context.insert(tx)
        }
        context.insert(BudgetModel(amount: 3000, ledgerKey: "life"))
        try? context.save()
    }
}
#endif
