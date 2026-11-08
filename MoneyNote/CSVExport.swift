import Foundation

enum CSVExport {
    nonisolated static func escape(_ value: String) -> String {
        // User-written labels must not become formulas in a spreadsheet.
        let protected = value.first.map { "=+@-\t\r".contains($0) } == true ? "'" + value : value
        return "\"" + protected.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

extension CSVExport {
    static func days(from start: Date, through end: Date, calendar: Calendar = .current) -> Range<Date>? {
        let first = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        guard first <= last, let exclusiveEnd = calendar.date(byAdding: .day, value: 1, to: last) else { return nil }
        return first..<exclusiveEnd
    }
}
