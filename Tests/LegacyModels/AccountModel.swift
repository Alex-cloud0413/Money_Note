//
//  AccountModel.swift
//  MoneyNote
//
//  账户：现金 / 银行卡 / 信用卡 等。余额随记账实时变化。
//

import Foundation
import SwiftData

/// 账户类型
enum AccountType: String, Codable, CaseIterable {
    case cash = "现金"
    case bank = "银行卡"
    case credit = "信用卡"
    case other = "其他"

    var defaultIcon: String {
        switch self {
        case .cash: return "💵"
        case .bank: return "🏦"
        case .credit: return "💳"
        case .other: return "👛"
        }
    }
}

@Model
final class AccountModel {
    var name: String = ""
    var icon: String = ""
    var typeRaw: String = "其他"
    /// 初始余额（建账户时账上已有多少钱；信用卡可填 0 或负的已用额度）
    var initialBalance: Double = 0
    var sortOrder: Int = 0
    /// 跨设备稳定标识，用于多端同步后的去重合并
    var uid: String = ""

    /// 属于这个账户的所有流水。删账户时把流水的 account 置空（保留流水）。
    @Relationship(deleteRule: .nullify, inverse: \TxRecord.account)
    var records: [TxRecord]?

    /// 用这个账户扣款的订阅。删账户时把订阅的 account 置空（CloudKit 要求关系有反向）。
    @Relationship(deleteRule: .nullify, inverse: \SubscriptionModel.account)
    var subscriptions: [SubscriptionModel]?

    init(name: String, icon: String, type: AccountType,
         initialBalance: Double = 0, sortOrder: Int = 0) {
        self.name = name
        self.icon = icon
        self.typeRaw = type.rawValue
        self.initialBalance = initialBalance
        self.sortOrder = sortOrder
        self.uid = UUID().uuidString
    }

    var type: AccountType {
        get { AccountType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    /// 实时余额 = 初始余额 + 该账户所有流水的带符号金额
    var balance: Double {
        initialBalance + (records ?? []).reduce(0) { $0 + $1.signedAmount }
    }

    // MARK: - 首次启动写入默认账户

    static func seedDefaultsIfNeeded(_ context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<AccountModel>())) ?? 0
        guard count == 0 else { return }
        context.insert(AccountModel(name: "现金", icon: "💵", type: .cash, sortOrder: 0))
        context.insert(AccountModel(name: "银行卡", icon: "🏦", type: .bank, sortOrder: 1))
        try? context.save()
    }
}
