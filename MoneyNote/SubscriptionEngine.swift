import Foundation
import SwiftData

enum SubscriptionEngine {

    /// 月份键，形如 "2026-06"
    static func monthKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    /// 某个月份的起始日（当月1号 0 点）
    private static func startOfMonth(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    /// The first allocation of each billing cycle represents the payment itself.
    static func isLaterAllocation(on date: Date, unit: AllocationUnit, for sub: SubscriptionModel,
                                  calendar: Calendar = .current) -> Bool {
        let firstDay = calendar.startOfDay(for: sub.startDate)
        let month = startOfMonth(date, calendar: calendar)
        let firstMonth = startOfMonth(firstDay, calendar: calendar)
        guard month >= firstMonth, unit == .month || date >= firstDay,
              let months = calendar.dateComponents([.month], from: firstMonth, to: month).month else {
            return false
        }
        if !months.isMultiple(of: sub.cycle.months) { return true }
        guard unit == .day, let renewal = calendar.date(byAdding: .month, value: months, to: firstDay) else {
            return false
        }
        return !calendar.isDate(date, inSameDayAs: renewal)
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

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        monthKey(date) + String(format: "-%02d", calendar.component(.day, from: date))
    }

    private struct Entry {
        var key: String
        var date: Date
        var amount: Double
        var foreignAmount: ForeignAmount?
    }

    private static func schedule(_ sub: SubscriptionModel, through endMonth: Date,
                                 calendar: Calendar) -> [Entry] {
        let firstDay = calendar.startOfDay(for: sub.startDate)
        let start = sub.allocation == .day ? firstDay : startOfMonth(firstDay, calendar: calendar)
        guard let end = calendar.date(byAdding: .month, value: 1, to: endMonth) else { return [] }
        let cycle = sub.cycle.months
        let foreign = sub.foreignAmount
        var monthOffset = 0
        var lastMonthKey: String?
        var entries: [Entry] = []

        while let cycleStart = calendar.date(byAdding: .month, value: monthOffset, to: start),
              cycleStart < end,
              let nextCycle = calendar.date(byAdding: .month, value: monthOffset + cycle, to: start) {
            // Anchor every renewal to the original billing day, including starts on the 29th–31st.
            let count = sub.allocation == .day
                ? (calendar.dateComponents([.day], from: cycleStart, to: nextCycle).day ?? 0)
                : cycle
            let firstCycle = monthOffset == 0
            let total = firstCycle ? sub.firstAmount : sub.amount
            let original = firstCycle ? sub.foreignFirstAmount ?? foreign?.original : foreign?.original
            for index in 0..<count {
                guard let date = sub.allocation.date(at: index, start: cycleStart, calendar: calendar),
                      date < end else { break }
                let month = monthKey(date)
                // Keep one legacy month key in every occupied month so older readers do not add a second charge.
                let key = sub.allocation == .day && month == lastMonthKey ? dayKey(date, calendar: calendar) : month
                lastMonthKey = month
                let entryDate = sub.allocation == .day ? date : dateInMonth(date, dayFrom: sub.startDate)
                let value = AllocationUnit.share(total: total, count: count, index: index)
                let originalShare = foreign.flatMap { foreign in
                    original.map { amount in
                        ForeignAmount(original: AllocationUnit.share(total: amount, count: count, index: index,
                                                                      scale: foreign.quote.currency.scale),
                                      quote: foreign.quote)
                    }
                }
                entries.append(Entry(key: key, date: entryDate, amount: value, foreignAmount: originalShare))
            }
            monthOffset += cycle
        }
        return entries
    }

    /// Sync through the selected month. Existing monthly charges keep their amounts unless explicitly edited.
    static func sync(_ context: ModelContext, upTo viewMonth: Date = .now, saving: Bool = true,
                     rewriteAmounts: Bool = false, only subscriptionID: String? = nil) throws {
        let subs = try context.fetch(FetchDescriptor<SubscriptionModel>())
            .filter { subscriptionID == nil || $0.uid == subscriptionID }
        guard !subs.isEmpty else { return }

        let allRecords = try context.fetch(FetchDescriptor<TxRecord>())
        let recordsByUID = Dictionary(grouping: allRecords.filter { !$0.subscriptionUID.isEmpty }, by: \.subscriptionUID)
        let calendar = Calendar.current
        let currentMonth = startOfMonth(.now)
        let endMonth = max(currentMonth, startOfMonth(viewMonth))
        let currentKey = monthKey(currentMonth)
        let today = calendar.startOfDay(for: .now)
        var changed = false

        for sub in subs {
            let records = recordsByUID[sub.uid] ?? []
            guard sub.isActive else {
                for record in records where record.allocation == .day
                    ? calendar.startOfDay(for: record.date) > today
                    : record.subscriptionMonthKey > currentKey {
                    context.delete(record)
                    changed = true
                }
                continue
            }

            let future = records.filter { $0.date > endMonth }.map { startOfMonth($0.date) }.max() ?? endMonth
            let scheduleEnd = rewriteAmounts ? max(endMonth, future) : endMonth
            var existing = Dictionary(grouping: records, by: \.subscriptionMonthKey)
            for entry in schedule(sub, through: scheduleEnd, calendar: calendar) {
                let matches = existing.removeValue(forKey: entry.key) ?? []
                let keep = matches.min {
                    if $0.isTrashed != $1.isTrashed { return $0.isTrashed }
                    return $0.createdAt < $1.createdAt
                }
                let record = keep ?? TxRecord(amount: entry.amount, type: .expense,
                                               categoryName: sub.categoryName, categoryIcon: sub.categoryIcon,
                                               subcategoryName: sub.subcategoryName, note: sub.name,
                                               date: entry.date)
                if keep == nil {
                    record.subscriptionUID = sub.uid
                    record.subscriptionMonthKey = entry.key
                    context.insert(record)
                    changed = true
                }
                let recalculate = rewriteAmounts || sub.allocation == .day
                if recalculate && record.amount != entry.amount { record.amount = entry.amount; changed = true }
                if recalculate && record.date != entry.date { record.date = entry.date; changed = true }
                if recalculate && record.allocation != sub.allocation {
                    record.allocation = sub.allocation
                    changed = true
                }
                if (recalculate || keep == nil), record.foreignAmount != entry.foreignAmount {
                    record.foreignAmount = entry.foreignAmount
                    changed = true
                }
                if record.ledgerKey != sub.ledgerKey { record.ledgerKey = sub.ledgerKey; changed = true }
                if record.categoryName != sub.categoryName { record.categoryName = sub.categoryName; changed = true }
                if record.categoryIcon != sub.categoryIcon { record.categoryIcon = sub.categoryIcon; changed = true }
                if record.subcategoryName != sub.subcategoryName { record.subcategoryName = sub.subcategoryName; changed = true }
                if record.note != sub.name { record.note = sub.name; changed = true }
                for duplicate in matches where duplicate !== record {
                    context.delete(duplicate)
                    changed = true
                }
            }

            if rewriteAmounts {
                for remaining in existing.values.flatMap({ $0 }) {
                    context.delete(remaining)
                    changed = true
                }
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
