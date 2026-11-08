import Foundation

enum InstallmentPlan {
    /// Whole cents guarantee positive installments and an exact total, including tiny amounts.
    static func amounts(total: Double, periods: Int) -> [Double] {
        guard total.isFinite, total > 0, total < 1_000_000_000, (2...60).contains(periods) else { return [] }
        let cents = Int((total * 100).rounded())
        guard cents >= periods else { return [] }
        return (0..<periods).map { AllocationUnit.share(total: total, count: periods, index: $0) }
    }
}

enum AllocationUnit: String, CaseIterable {
    case month = "按月"
    case day = "按天"

    var averageLabel: String { self == .day ? "每天平摊约" : "每月平摊约" }

    func count(start: Date, months: Int, calendar: Calendar = .current) -> Int {
        guard self == .day else { return months }
        let first = calendar.startOfDay(for: start)
        guard let end = calendar.date(byAdding: .month, value: months, to: first) else { return 0 }
        return calendar.dateComponents([.day], from: first, to: end).day ?? 0
    }

    func date(at index: Int, start: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(byAdding: self == .day ? .day : .month, value: index, to: start)
    }

    static func share(total: Double, count: Int, index: Int, scale: Double = 100) -> Double {
        guard count > 0, index >= 0, index < count, total.isFinite,
              total >= 0, total < 1_000_000_000 else { return 0 }
        let units = Int((total * scale).rounded())
        return Double(units / count + (index < units % count ? 1 : 0)) / scale
    }
}
