import SwiftUI
import SwiftData

struct CategoryManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CategoryModel.sortOrder) private var categories: [CategoryModel]
    @State private var type = TransactionType.expense
    @State private var editing: CategoryModel?
    @State private var adding = false
    @State private var childParent: CategoryModel?
    @State private var showArchived = false
    var body: some View {
        NavigationStack {
            PaperList {
                Section {
                    Picker("收支类型", selection: $type) {
                        ForEach(TransactionType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    Toggle("显示已归档分类", isOn: $showArchived)
                }
                ForEach(categories.filter { $0.parent == nil && $0.type == type && (showArchived || !$0.isArchived) }) { parent in
                    Section {
                        Button { editing = parent } label: { categoryRow(parent) }
                        ForEach(parent.sortedChildren.filter { showArchived || !$0.isArchived }) { child in
                            Button { editing = child } label: {
                                HStack { Image(systemName: "arrow.turn.down.right").accessibilityHidden(true); categoryRow(child) }
                            }
                        }
                        Button { childParent = parent } label: { Label("添加子类", systemImage: "plus").frame(minHeight: 44) }
                    }.listRowBackground(PaperTheme.surface)
                }
                Section { Button { adding = true } label: { Label("添加大类", systemImage: "plus.circle").frame(minHeight: 44) } }
                Section { Text("归档分类会保留历史账目和统计；需要时可以恢复。每次修改在编辑页保存后生效。")
                    .font(.footnote).foregroundStyle(.secondary) }
            }.paperScreen().navigationTitle("分类管理").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .sheet(item: $editing) { CategoryEditForm(editing: $0, parent: $0.parent, type: $0.type) }
                .sheet(isPresented: $adding) { CategoryEditForm(type: type) }
                .sheet(item: $childParent) { CategoryEditForm(parent: $0, type: $0.type) }
        }
    }
    private func categoryRow(_ category: CategoryModel) -> some View {
        HStack {
            CategoryGlyph(name: category.name, icon: category.icon, size: 36)
            Text(category.name)
            Spacer()
            if category.isArchived { Text("已归档").font(.caption).foregroundStyle(.secondary) }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }.frame(minHeight: 44).contentShape(Rectangle())
    }
}

struct CategoryEditForm: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSession
    var editing: CategoryModel? = nil
    var parent: CategoryModel? = nil
    var type: TransactionType
    @State private var name = ""
    @State private var icon = "tag"
    @State private var baseline = ""
    @State private var setupDone = false
    @State private var discard = false
    @State private var archive = false
    @State private var error: String?
    private var dirty: Bool { setupDone && name + "|" + icon != baseline }
    private var validation: String? {
        do { try CategoryOperations.validate(name.trimmingCharacters(in: .whitespacesAndNewlines), category: editing,
                                           parent: parent, type: type, in: context); return nil }
        catch { return error.localizedDescription }
    }
    var body: some View {
        NavigationStack {
            PaperForm {
                Section(parent == nil ? "大类" : "子类 · \(parent!.name)") {
                    TextField("分类名称", text: $name)
                    SymbolPicker(icon: $icon, name: name)
                    InlineValidation(message: name.isEmpty ? nil : validation)
                }
                Section { Text("改名后，历史账目、订阅、预算与关注分类会一起更新。")
                    .font(.footnote).foregroundStyle(.secondary) }
                if let editing {
                    Section {
                        Button(editing.archived == true ? "恢复分类" : "归档分类") { archive = true }
                    } footer: { Text("归档不删除历史账目。大类归档时，其子类一并隐藏。") }
                }
            }.paperScreen().navigationTitle(editing == nil ? "添加分类" : "编辑分类").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { if dirty { discard = true } else { dismiss() } } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(validation != nil) }
                }
                .onAppear {
                    guard !setupDone else { return }
                    name = editing?.name ?? ""; icon = editing?.icon ?? parent?.icon ?? "tag"
                    baseline = name + "|" + icon; setupDone = true
                }
                .protectDraft(dirty, confirming: $discard) { dismiss() }
                .confirmationDialog(editing?.archived == true ? "恢复这个分类？" : "归档这个分类？", isPresented: $archive, titleVisibility: .visible) {
                    Button(editing?.archived == true ? "恢复分类" : "归档分类") {
                        guard let editing else { return }
                        editing.archived = !(editing.archived ?? false)
                        do { try context.save(); session.saved(editing.isArchived ? "分类已归档，历史账目已保留" : "分类已恢复"); dismiss() }
                        catch { context.rollback(); self.error = "操作未完成，请重试。" }
                    }
                } message: { Text("此操作只改变分类是否出现在新账选择中，历史记录仍然保留。") }
                .alert("未能保存", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("好") { error = nil }
                } message: { Text(error ?? "") }
        }
    }
    private func save() {
        guard validation == nil else { return }
        do {
            if let editing { try CategoryOperations.update(editing, name: name, icon: icon, in: context) }
            else {
                let siblings = try context.fetch(FetchDescriptor<CategoryModel>()).filter { $0.parent === parent && $0.type == type }
                context.insert(CategoryModel(name: name.trimmingCharacters(in: .whitespacesAndNewlines), icon: icon,
                                              type: type, sortOrder: (siblings.map(\.sortOrder).max() ?? -1) + 1, parent: parent))
                try context.save()
            }
            session.saved("分类已保存"); dismiss()
        } catch { context.rollback(); self.error = error.localizedDescription }
    }
}
