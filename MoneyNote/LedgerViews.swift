import SwiftUI
import SwiftData

struct LedgerPicker: View {
    @Query private var models: [LedgerModel]
    @AppStorage("selectedLedger") private var selected = LedgerChoice.legacyKey
    var body: some View {
        let choices = LedgerChoice.choices(models)
        Menu {
            Picker("当前账本", selection: $selected) {
                ForEach(choices) { book in Text(book.name).tag(book.id) }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "book.closed")
                Text(choices.first { $0.id == selected }?.name ?? "生活账本")
                Image(systemName: "chevron.down").font(.caption2)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(PaperTheme.soft, in: Capsule())
        }
        .accessibilityIdentifier("ledgerPicker")
        .accessibilityLabel("切换账本")
        .accessibilityValue(choices.first { $0.id == selected }?.name ?? "生活账本")
    }
}

struct LedgersView: View {
    @EnvironmentObject private var session: AppSession
    @Query private var models: [LedgerModel]
    @Query private var records: [TxRecord]
    @AppStorage("selectedLedger") private var selected = LedgerChoice.legacyKey
    @State private var editing: LedgerChoice?
    @State private var adding = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("把生活与事业，各自记好。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    MonthPicker(month: $session.month)
                    ForEach(LedgerChoice.choices(models)) { book in
                        VStack(alignment: .leading, spacing: 20) {
                            HStack {
                                Image(systemName: book.id == "work" ? "briefcase" : "book.closed")
                                    .font(.title2)
                                Text(book.name).font(.title3.weight(.medium))
                                Spacer()
                                Button { editing = book } label: {
                                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                                }.accessibilityLabel("编辑" + book.name)
                            }
                            let entries = LedgerAnalytics.records(records, ledger: book.id, month: session.month)
                            AdaptiveRow {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("所选月份支出").font(.caption).foregroundStyle(.secondary)
                                    Text(entries.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }.asCurrency)
                                        .font(.system(.title, design: .serif)).monospacedDigit()
                                }
                                AdaptiveSpacer()
                                Button { selected = book.id; session.selection = 0 } label: {
                                    Label("进入账本",
                                          systemImage: selected == book.id ? "checkmark.circle.fill" : "arrow.right")
                                        .font(.subheadline).padding(.vertical, 10)
                                }
                            }
                            Text("所选月份 \(entries.count) 笔记录")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(22).paperCard()
                    }
                    Button { adding = true } label: {
                        Label("新建账本", systemImage: "plus").frame(maxWidth: .infinity).padding(18)
                    }.paperCard()
                    Text("每个账本独立汇总明细、统计、预算与订阅，适合区分生活、事业或其他用途。")
                        .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
                }.padding(20).readableWidth()
            }
            .paperScreen().navigationTitle("账本").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $adding) { LedgerEditor() }
            .sheet(item: $editing) { LedgerEditor(editing: $0) }
        }
    }
}

struct LedgerEditor: View {
    @EnvironmentObject private var session: AppSession
    @State private var baseline = ""
    @State private var setupDone = false
    @State private var discard = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var models: [LedgerModel]
    var editing: LedgerChoice? = nil
    @State private var name = ""
    @State private var error: String?
    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var valid: Bool {
        !cleanName.isEmpty && cleanName.count <= 24 &&
        !LedgerChoice.choices(models).contains { $0.name == cleanName && $0.id != editing?.id }
    }
    var body: some View {
        NavigationStack {
            PaperForm {
                Section("账本名称") {
                    TextField("如：生活账本、事业账本", text: $name)
                    if !cleanName.isEmpty && !valid {
                        InlineValidation(message: cleanName.count > 24 ? "名称最多 24 个字。" : "已有同名账本，请换一个名称。")
                    }
                }
                Section {
                    Text("明细、统计和预算会按账本分别展示。更改名称不会影响已有账目。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.paperScreen()
                .navigationTitle(editing == nil ? "新建账本" : "编辑账本")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { if name != baseline { discard = true } else { dismiss() } } }
                    ToolbarItem(placement: .confirmationAction) { Button("完成", action: save).disabled(!valid) }
                }
                .onAppear { guard !setupDone else { return }; name = editing?.name ?? ""; baseline = name; setupDone = true }
                .protectDraft(setupDone && name != baseline, confirming: $discard) { dismiss() }
                .alert("未能保存", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("好") { error = nil }
                } message: { Text(error ?? "") }
        }
    }
    private func save() {
        guard valid else { return }
        if let key = editing?.id, let model = models.first(where: { $0.key == key }) {
            model.name = cleanName
            model.updatedAt = .now
        } else {
            context.insert(LedgerModel(key: editing?.id ?? UUID().uuidString, name: cleanName))
        }
        do { try context.save(); session.saved("账本已保存"); dismiss() } catch { context.rollback(); self.error = "请稍后重试，账本尚未保存。" }
    }
}
