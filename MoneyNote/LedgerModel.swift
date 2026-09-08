import Foundation
import SwiftData

/// Stable keys keep account relationships intact and avoid CloudKit uniqueness constraints.
@Model
final class LedgerModel {
    var key: String = ""
    var name: String = ""
    var updatedAt: Date = Date.now

    init(key: String = UUID().uuidString, name: String) {
        self.key = key
        self.name = name
        self.updatedAt = .now
    }
}

struct LedgerChoice: Identifiable, Equatable {
    let id: String
    let name: String
    static let legacyKey = "life"

    static func choices(_ models: [LedgerModel]) -> [LedgerChoice] {
        var names = ["life": "生活账本", "work": "事业账本"]
        // Concurrent edits converge deterministically; no seed records need merging.
        for model in models.sorted(by: {
            $0.updatedAt == $1.updatedAt ? $0.name < $1.name : $0.updatedAt < $1.updatedAt
        }) where !model.key.isEmpty && !model.name.isEmpty {
            names[model.key] = model.name
        }
        let keys = ["life", "work"] + names.keys.filter { $0 != "life" && $0 != "work" }.sorted()
        return keys.map { LedgerChoice(id: $0, name: names[$0]!) }
    }
}

/// Shared by the chart and its drill-down so every percentage uses the same scope.
struct CategoryTotal: Identifiable {
    var id: String { name }
    let name: String
    let amount: Double
    let share: Double
}

enum LedgerAnalytics {
    static func records(_ records: [TxRecord], ledger: String, month: Date,
                        type: TransactionType? = nil, parent: String? = nil) -> [TxRecord] {
        records.filter {
            $0.ledgerKey == ledger &&
            Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) &&
            (type == nil || $0.type == type) && (parent == nil || $0.categoryName == parent)
        }
    }

    static func categories(_ records: [TxRecord], children: Bool = false) -> [CategoryTotal] {
        let total = records.reduce(0) { $0 + $1.amount }
        return Dictionary(grouping: records) {
            children ? ($0.subcategoryName.isEmpty ? "未分子类" : $0.subcategoryName) : $0.categoryName
        }.map { name, values in
            let amount = values.reduce(0) { $0 + $1.amount }
            return CategoryTotal(name: name, amount: amount, share: total > 0 ? amount / total : 0)
        }.sorted { $0.amount == $1.amount ? $0.name < $1.name : $0.amount > $1.amount }
    }
}
