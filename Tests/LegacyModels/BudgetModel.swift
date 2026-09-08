//
//  BudgetModel.swift
//  MoneyNote
//
//  预算：每月的支出上限。categoryName 为空表示「总预算」，
//  否则是某个分类的预算。预算每月重复生效，花销按当月统计。
//

import Foundation
import SwiftData

@Model
final class BudgetModel {
    /// 分类名；空字符串表示总预算
    var categoryName: String = ""
    /// 每月预算金额
    var amount: Double = 0
    var sortOrder: Int = 0

    init(categoryName: String = "", amount: Double, sortOrder: Int = 0) {
        self.categoryName = categoryName
        self.amount = amount
        self.sortOrder = sortOrder
    }

    /// 是不是总预算
    var isTotal: Bool { categoryName.isEmpty }
}
