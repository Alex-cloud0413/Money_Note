//
//  BudgetModel.swift
//  MoneyNote
//
//  预算：某个具体月份的支出上限。categoryName 为空表示「总预算」，
//  否则是某个分类的预算。每个月独立设置，互不继承。
//

import Foundation
import SwiftData

@Model
final class BudgetModel {
    /// Nil preserves existing and late-arriving CloudKit records in the life ledger.
    var bookID: String? = nil
    /// Current records use YYYY-MM. Nil is retained only while an old record awaits migration.
    var monthKey: String? = nil
    var ledgerKey: String {
        get { bookID ?? LedgerChoice.legacyKey }
        set { bookID = newValue }
    }

    /// 分类名；空字符串表示总预算
    var categoryName: String = ""
    /// 这个月份的预算金额
    var amount: Double = 0
    var sortOrder: Int = 0

    init(categoryName: String = "", amount: Double, sortOrder: Int = 0, ledgerKey: String = "life") {
        self.categoryName = categoryName
        self.amount = amount
        self.sortOrder = sortOrder
        self.bookID = ledgerKey
    }

    /// 是不是总预算
    var isTotal: Bool { categoryName.isEmpty }
}


enum BudgetRules {
    static func effective(_ budgets: [BudgetModel], ledger: String, month: Date) -> [BudgetModel] {
        let key = SubscriptionEngine.monthKey(month)
        let candidates = budgets.filter { $0.ledgerKey == ledger && $0.monthKey == key }
        return Dictionary(grouping: candidates, by: \.categoryName).compactMap { _, group in group.first }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
}
