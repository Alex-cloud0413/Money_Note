//
//  SubscriptionModel.swift
//  MoneyNote
//
//  订阅制支出（自动续费）的数据结构。
//  记录续费周期、每期扣款、首次开通日期与首期金额（很多软件首期有优惠），
//  由 SubscriptionEngine 按月平摊并自动生成真实流水。
//

import Foundation
import SwiftData

/// 续费周期：每月 / 每季 / 每年
enum BillingCycle: String, Codable, CaseIterable {
    case monthly = "每月"
    case quarterly = "每季"
    case yearly = "每年"

    /// 一个周期包含几个月
    var months: Int {
        switch self {
        case .monthly: return 1
        case .quarterly: return 3
        case .yearly: return 12
        }
    }
}

@Model
final class SubscriptionModel {
    /// 订阅名称，例如「爱奇艺会员」
    var name: String = ""
    /// 续费周期，底层存字符串（"每月"/"每季"/"每年"）
    var cycleRaw: String = "每月"
    /// 每期常规扣款金额
    var amount: Double = 0
    /// 首期金额（首次开通价，常有优惠）；没有优惠时与 amount 相同
    var firstAmount: Double = 0
    /// 首次开通自动续费的日期
    var startDate: Date = Date.now

    /// 平摊后的支出计入哪个大类
    var categoryName: String = ""
    /// 大类图标
    var categoryIcon: String = "🔁"
    /// 子类（可为空）
    var subcategoryName: String = ""

    /// 扣款账户（可为空）
    var account: AccountModel?

    /// 是否仍在订阅中（取消后置 false，停止继续生成）
    var isActive: Bool = true
    /// 备注
    var note: String = ""
    /// 排序用
    var sortOrder: Int = 0
    /// 创建时间
    var createdAt: Date = Date.now
    /// 稳定标识，用于把生成的流水关联回这个订阅、以及多端去重
    var uid: String = ""

    init(name: String,
         cycle: BillingCycle,
         amount: Double,
         firstAmount: Double,
         startDate: Date,
         categoryName: String,
         categoryIcon: String,
         subcategoryName: String = "",
         note: String = "",
         sortOrder: Int = 0) {
        self.name = name
        self.cycleRaw = cycle.rawValue
        self.amount = amount
        self.firstAmount = firstAmount
        self.startDate = startDate
        self.categoryName = categoryName
        self.categoryIcon = categoryIcon
        self.subcategoryName = subcategoryName
        self.note = note
        self.isActive = true
        self.sortOrder = sortOrder
        self.createdAt = .now
        self.uid = UUID().uuidString
    }

    /// 方便用枚举读写周期
    var cycle: BillingCycle {
        get { BillingCycle(rawValue: cycleRaw) ?? .monthly }
        set { cycleRaw = newValue.rawValue }
    }

    /// 每月平摊金额（按常规价），保留两位
    var monthlyAmortized: Double {
        ((amount / Double(cycle.months)) * 100).rounded() / 100
    }

    /// 是否设置了首期优惠（首期金额与常规价不同）
    var hasFirstPromo: Bool { abs(firstAmount - amount) > 0.001 }
}
