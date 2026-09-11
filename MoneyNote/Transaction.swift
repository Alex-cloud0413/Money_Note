//
//  Transaction.swift
//  MoneyNote
//
//  一笔账的数据结构（账单流水）。
//  类型名用 TxRecord，避免和 SwiftUI 自带的 Transaction 撞名。
//

import Foundation
import SwiftData

/// 收支类型：支出 / 收入
enum TransactionType: String, Codable, CaseIterable {
    case expense = "支出"
    case income = "收入"
}

/// 一笔账单流水。@Model 表示它会被 SwiftData 自动存到本地数据库。
@Model
final class TxRecord {
    /// Soft deletion preserves all relationships and supports recovery across restarts.
    var deletedAt: Date? = nil
    var isTrashed: Bool { deletedAt != nil }
    /// Nil preserves existing and late-arriving CloudKit records in the life ledger.
    var bookID: String? = nil
    var ledgerKey: String {
        get { bookID ?? LedgerChoice.legacyKey }
        set { bookID = newValue }
    }

    /// 金额，永远存正数（用 type 区分收/支）
    var amount: Double = 0
    /// 收支类型，底层存字符串（"支出"/"收入"），更稳妥
    var typeRaw: String = "支出"
    /// 大类名称，例如「餐饮」
    var categoryName: String = ""
    /// 大类图标（emoji），例如 "🍜"
    var categoryIcon: String = ""
    /// 子类名称，可为空字符串（表示没选子类）
    var subcategoryName: String = ""
    /// 备注
    var note: String = ""
    /// 账单发生的日期（用户可改）
    var date: Date = Date.now
    /// 这条记录创建的时间（用于同一天内排序）
    var createdAt: Date = Date.now

    /// Legacy migration field. New versions neither display nor write account data.
    var account: AccountModel?

    // —— 分期相关 ——
    /// 同一组分期共用一个 ID；非分期为 nil
    var installmentGroupID: UUID? = nil
    /// 这是第几期（从 1 开始）
    var installmentIndex: Int = 1
    /// 总共几期（1 表示不是分期）
    var installmentCount: Int = 1

    // —— 订阅相关（由 SubscriptionEngine 自动生成的平摊流水）——
    /// 来源订阅的 uid；空字符串表示不是订阅生成的普通流水
    var subscriptionUID: String = ""
    /// 这笔订阅流水属于哪个月，形如 "2026-06"，用于「订阅×月份」去重
    var subscriptionMonthKey: String = ""

    init(amount: Double,
         type: TransactionType,
         categoryName: String,
         categoryIcon: String,
         subcategoryName: String = "",
         note: String = "",
         date: Date = .now,
         installmentGroupID: UUID? = nil,
         installmentIndex: Int = 1,
         installmentCount: Int = 1) {
        self.amount = amount
        self.typeRaw = type.rawValue
        self.categoryName = categoryName
        self.categoryIcon = categoryIcon
        self.subcategoryName = subcategoryName
        self.note = note
        self.date = date
        self.createdAt = .now
        self.installmentGroupID = installmentGroupID
        self.installmentIndex = installmentIndex
        self.installmentCount = installmentCount
    }

    /// 方便用枚举读写 type
    var type: TransactionType {
        get { TransactionType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }

    /// 带符号的金额：支出为负、收入为正，方便算结余
    var signedAmount: Double {
        type == .expense ? -amount : amount
    }

    /// 列表上显示的类别文字：有子类就显示「餐饮 · 外卖」
    var displayCategory: String {
        subcategoryName.isEmpty ? categoryName : "\(categoryName) · \(subcategoryName)"
    }

    /// 是不是分期里的一笔
    var isInstallment: Bool { installmentCount > 1 }

    /// 是不是订阅自动生成的平摊流水
    var isSubscription: Bool { !subscriptionUID.isEmpty }
}
