import Foundation

enum CSVExport {
    nonisolated static func escape(_ value: String) -> String {
        // User-written labels must not become formulas in a spreadsheet.
        let protected = value.first.map { "=+@-\t\r".contains($0) } == true ? "'" + value : value
        return "\"" + protected.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
