import Foundation

enum InstallmentPlan {
    /// Whole cents guarantee positive installments and an exact total, including tiny amounts.
    static func amounts(total: Double, periods: Int) -> [Double] {
        guard total.isFinite, total > 0, total < 1_000_000_000, (2...60).contains(periods) else { return [] }
        let cents = Int((total * 100).rounded())
        guard cents >= periods else { return [] }
        let base = cents / periods
        let remainder = cents % periods
        return (0..<periods).map { Double(base + ($0 < remainder ? 1 : 0)) / 100 }
    }
}
