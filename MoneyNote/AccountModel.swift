//
//  AccountModel.swift
//  MoneyNote
//
//  Legacy storage compatibility only. The account feature is retired in 1.3.
//  Keep this entity in the schema so existing local and CloudKit stores remain readable.
//

import Foundation
import SwiftData

@Model
final class AccountModel {
    var name: String = ""
    var icon: String = ""
    var typeRaw: String = "其他"
    var initialBalance: Double = 0
    var sortOrder: Int = 0
    /// 跨设备稳定标识，用于多端同步后的去重合并
    var uid: String = ""
    var archived: Bool? = nil
    var isArchived: Bool { archived == true }
    /// Relationships remain solely for automatic migration of older stores.
    @Relationship(deleteRule: .nullify, inverse: \TxRecord.account)
    var records: [TxRecord]?

    @Relationship(deleteRule: .nullify, inverse: \SubscriptionModel.account)
    var subscriptions: [SubscriptionModel]?

    /// Required by SwiftData when opening an older store. Product code must not create this model.
    init(name: String = "", icon: String = "", typeRaw: String = "其他",
         initialBalance: Double = 0, sortOrder: Int = 0, uid: String = "") {
        self.name = name
        self.icon = icon
        self.typeRaw = typeRaw
        self.initialBalance = initialBalance
        self.sortOrder = sortOrder
        self.uid = uid
    }
}
