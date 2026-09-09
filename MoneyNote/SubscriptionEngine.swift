//
//  SubscriptionEngine.swift
//  MoneyNote
//
//  把每个订阅按月「平摊」并自动生成真实流水：
//  年付/季付按周期月数平摊，每个月生成一笔支出，自动计入月度汇总、统计、预算。
//  首期金额（优惠价）只在首个周期的那几个月里平摊。
//
//  生成的流水带 subscriptionUID 标记，可识别、可统一更新/删除；
//  每个「订阅 × 月份」只保留一笔（按 subscriptionMonthKey 去重）。
//

import Foundation
import SwiftData

enum SubscriptionEngine {

    /// 月份键，形如 "2026-06"
    static func monthKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    /// 某个月份的起始日（当月1号 0 点）
    private static func startOfMonth(_ date: Date) -> Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
    }

    /// 把订阅开通日的「号数」套用到目标月份（超出当月天数则取当月最后一天）
    private static func dateInMonth(_ month: Date, dayFrom start: Date) -> Date {
        let cal = Calendar.current
        let day = cal.component(.day, from: start)
        let range = cal.range(of: .day, in: .month, for: month)?.count ?? 28
        var comps = cal.dateComponents([.year, .month], from: month)
        comps.day = min(day, range)
        comps.hour = 12
        return cal.date(from: comps) ?? month
    }

    /// 同步所有订阅：补齐/更新从开通月到当前月的每月平摊流水，并清理重复。
    /// 在 App 启动、iCloud 远程变更、以及新增/编辑订阅后调用。
    /// viewMonth：用户正在查看的月份；翻到未来月份时会把订阅平摊记录补到该月。
    static func sync(_ context: ModelContext, upTo viewMonth: Date = .now, saving: Bool = true, rewriteAmounts: Bool = false) throws {
        let subs = try context.fetch(FetchDescriptor<SubscriptionModel>())
        guard !subs.isEmpty else { return }

        // 一次取出所有「订阅生成」的流水，按 uid 分组
        let allRecords = try context.fetch(FetchDescriptor<TxRecord>())
        var recordsByUID: [String: [TxRecord]] = [:]
        for r in allRecords where !r.subscriptionUID.isEmpty {
            recordsByUID[r.subscriptionUID, default: []].append(r)
        }

        let cal = Calendar.current
        let currentMonth = startOfMonth(.now)
        // 生成到「当前月」与「正在查看的月份」中较晚的那个：翻到未来月份时按需补上
        let endMonth = max(currentMonth, startOfMonth(viewMonth))
        let currentKey = monthKey(currentMonth)
        var changed = false

        for sub in subs {
            // 该订阅已生成流水，按月份键分组
            var existing: [String: [TxRecord]] = [:]
            for r in recordsByUID[sub.uid] ?? [] {
                existing[r.subscriptionMonthKey, default: []].append(r)
            }

            // 已取消的订阅：保留历史，但清掉「未来月份」（晚于当前月）已生成的平摊记录，不再生成新的
            guard sub.isActive else {
                for (key, recs) in existing where key > currentKey {
                    for r in recs { context.delete(r); changed = true }
                }
                continue
            }

            let startMonth = startOfMonth(sub.startDate)
            guard startMonth <= endMonth else { continue }   // 开通日在查看范围之后，暂不生成

            let cycleMonths = max(1, sub.cycle.months)

            var month = startMonth
            while month <= endMonth {
                let key = monthKey(month)
                let monthsSinceStart = cal.dateComponents([.month], from: startMonth, to: month).month ?? 0
                let periodIndex = monthsSinceStart / cycleMonths
                let periodAmount = (periodIndex == 0) ? sub.firstAmount : sub.amount
                guard periodAmount.isFinite, periodAmount >= 0, periodAmount < 1_000_000_000 else { break }
                let cents = Int((periodAmount * 100).rounded())
                let offset = monthsSinceStart % cycleMonths
                let amt = Double(cents / cycleMonths + (offset < cents % cycleMonths ? 1 : 0)) / 100

                if let recs = existing[key], let keep = recs.first {
                    // 已有：仅当值真的变了才赋值（保持幂等，避免反复变脏触发多余保存/同步抖动）
                    if keep.ledgerKey != sub.ledgerKey { keep.ledgerKey = sub.ledgerKey; changed = true }
                    if rewriteAmounts && keep.amount != amt { keep.amount = amt; changed = true }
                    if keep.categoryName != sub.categoryName { keep.categoryName = sub.categoryName; changed = true }
                    if keep.categoryIcon != sub.categoryIcon { keep.categoryIcon = sub.categoryIcon; changed = true }
                    if keep.subcategoryName != sub.subcategoryName { keep.subcategoryName = sub.subcategoryName; changed = true }
                    if keep.note != sub.name { keep.note = sub.name; changed = true }
                    if keep.account?.persistentModelID != sub.account?.persistentModelID {
                        keep.account = sub.account; changed = true
                    }
                    for dup in recs.dropFirst() { context.delete(dup); changed = true }
                } else {
                    // 缺失：补一笔
                    let rec = TxRecord(amount: amt, type: .expense,
                                       categoryName: sub.categoryName,
                                       categoryIcon: sub.categoryIcon,
                                       subcategoryName: sub.subcategoryName,
                                       note: sub.name,
                                       date: dateInMonth(month, dayFrom: sub.startDate))
                    rec.account = sub.account
                    rec.ledgerKey = sub.ledgerKey
                    rec.subscriptionUID = sub.uid
                    rec.subscriptionMonthKey = key
                    context.insert(rec)
                    changed = true
                }

                guard let next = cal.date(byAdding: .month, value: 1, to: month) else { break }
                month = next
            }
        }

        if changed && saving { try context.save() }
    }

    /// 删除某个订阅时，连同它生成的所有流水一起删除。
    static func deleteRecords(for sub: SubscriptionModel, in context: ModelContext) throws {
        let uid = sub.uid
        let all = try context.fetch(FetchDescriptor<TxRecord>())
        for r in all where r.subscriptionUID == uid {
            context.delete(r)
        }
    }
}
