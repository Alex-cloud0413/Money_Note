import SwiftUI
import SwiftData

struct PinnedCategoryCards: View {
    let records: [TxRecord]
    @AppStorage("selectedLedger") private var ledger = LedgerChoice.legacyKey
    var body: some View { PinnedLedgerCards(ledger: ledger, records: records).id(ledger) }
}
private struct PinnedLedgerCards: View {
    let records: [TxRecord]
    @AppStorage private var raw: String
    @Query private var categories: [CategoryModel]
    @State private var expanded = false
    init(ledger: String, records: [TxRecord]) {
        self.records = records
        _raw = AppStorage(wrappedValue: "", ledger == "life" ? "pinnedCategoryNames" : "pinnedCategoryNames." + ledger)
    }
    private var names: [String] { CategoryOperations.resolvedPins(raw, categories: categories) }
    var body: some View {
        if !names.isEmpty {
            DisclosureGroup("关注分类", isExpanded: $expanded) {
                ForEach(names, id: \.self) { name in
                    AdaptiveRow {
                        HStack { CategoryGlyph(name: name, icon: categories.first { $0.parent == nil && $0.type == .expense && $0.name == name }?.icon ?? "", size: 30); Text(name) }
                        AdaptiveSpacer()
                        MoneyText(value: records.filter { !$0.isTrashed && $0.type == .expense && $0.categoryName == name }.reduce(0) { $0 + $1.amount })
                    }.padding(.vertical, 8)
                }
            }.font(.subheadline).padding(16).paperCard()
        }
    }
}
struct PinnedCategoryPicker: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("selectedLedger") private var ledger = LedgerChoice.legacyKey
    var body: some View {
        NavigationStack {
            VStack { LedgerPicker(); PinnedSelection(ledger: ledger).id(ledger) }
                .paperScreen().navigationTitle("关注分类").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
private struct PinnedSelection: View {
    @AppStorage private var raw: String
    @Query(sort: \CategoryModel.sortOrder) private var categories: [CategoryModel]
    init(ledger: String) { _raw = AppStorage(wrappedValue: "", ledger == "life" ? "pinnedCategoryNames" : "pinnedCategoryNames." + ledger) }
    private var names: [String] { CategoryOperations.resolvedPins(raw, categories: categories) }
    var body: some View {
        PaperList {
            Section { Text("选中后立即生效，仅影响当前账本。在明细页展开「关注分类」即可查看所选月份的支出。")
                .font(.footnote).foregroundStyle(.secondary) }
            ForEach(categories.filter { $0.parent == nil && $0.type == .expense && (!$0.isArchived || names.contains($0.name)) }) { category in
                Button {
                    var selected = names
                    if selected.contains(category.name) { selected.removeAll { $0 == category.name } } else { selected.append(category.name) }
                    raw = selected.joined(separator: "\n")
                } label: {
                    HStack {
                        CategoryGlyph(name: category.name, icon: category.icon)
                        Text(category.name); Spacer()
                        if names.contains(category.name) { Image(systemName: "checkmark") }
                    }.frame(minHeight: 44)
                }.accessibilityAddTraits(names.contains(category.name) ? .isSelected : [])
                    .listRowBackground(PaperTheme.surface)
            }
        }.scrollContentBackground(.hidden)
    }
}
