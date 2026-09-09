import SwiftUI
import SwiftData

struct AccountsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \AccountModel.sortOrder) private var accounts: [AccountModel]
    @State private var editing: AccountModel?
    @State private var adding = false
    var body: some View {
        NavigationStack {
            PaperList {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("当前账面余额").font(.subheadline).foregroundStyle(.secondary)
                        MoneyText(value: accounts.reduce(0) { $0 + $1.balance }, style: .largeTitle)
                        Text("所有账本共用账户；余额按截至现在的账目计算，包含已归档账户，未来计划暂不计入。订阅按月平摊，不代表银行实时余额。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
                Section("使用中的账户") {
                    ForEach(accounts.filter { !$0.isArchived }) { row($0) }
                    Button { adding = true } label: { Label("添加账户", systemImage: "plus.circle").frame(minHeight: 44) }
                }
                if accounts.contains(where: \.isArchived) {
                    Section("已归档 · 可恢复") { ForEach(accounts.filter(\.isArchived)) { row($0) } }
                }
            }.readableWidth().paperScreen().navigationTitle("资金账户")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .sheet(item: $editing) { AccountEditView(account: $0) }
                .sheet(isPresented: $adding) { AccountEditView(account: nil) }
        }
    }
    private func row(_ account: AccountModel) -> some View {
        Button { editing = account } label: { AccountRow(account: account) }.buttonStyle(.plain)
            .listRowBackground(PaperTheme.surface)
    }
}
struct AccountRow: View {
    let account: AccountModel
    var body: some View {
        AdaptiveRow {
            HStack {
                CategoryGlyph(name: account.type.rawValue, icon: account.icon)
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.name)
                    Text(account.type.rawValue + (account.isArchived ? " · 已归档" : "")).font(.caption).foregroundStyle(.secondary)
                }
            }
            AdaptiveSpacer()
            MoneyText(value: account.balance)
        }.padding(.vertical, 6).accessibilityElement(children: .combine)
    }
}
struct AccountEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSession
    @Query private var accounts: [AccountModel]
    var account: AccountModel?
    @State private var name = ""
    @State private var icon = "banknote"
    @State private var type = AccountType.cash
    @State private var balanceText = "0"
    @State private var baseline = ""
    @State private var didSetup = false
    @State private var discard = false
    @State private var archive = false
    @State private var error: String?
    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var fingerprint: String { [name, icon, type.rawValue, balanceText].joined(separator: "|") }
    private var dirty: Bool { didSetup && fingerprint != baseline }
    private var validation: String? {
        if cleanName.isEmpty || cleanName.count > 24 { return "账户名称请填写 1–24 个字。" }
        if accounts.contains(where: { $0 !== account && $0.name == cleanName && $0.type == type }) { return "这个类型中已有同名账户。" }
        guard let value = Double(balanceText), value.isFinite, abs(value) < 1_000_000_000 else { return "请输入有效的初始余额，可用负数表示欠款。" }
        return nil
    }
    var body: some View {
        NavigationStack {
            PaperForm {
                Section("账户信息") {
                    TextField("名称，如：招商银行", text: $name)
                    SymbolPicker(icon: $icon, name: name)
                    Picker("类型", selection: $type) {
                        ForEach(AccountType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }
                Section {
                    LabeledContent("初始余额") { TextField("0", text: $balanceText).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing) }
                    InlineValidation(message: validation)
                } header: { Text("开始记账时的金额") } footer: {
                    Text("后续账目会在此基础上增减。更改初始余额会重新计算账户余额，信用卡欠款可填负数。")
                }
                if let account {
                    Section { Button(account.isArchived ? "恢复账户" : "归档账户") { archive = true } }
                    footer: { Text("归档后，新账不再提供这个账户；历史记录与账户关系会保留。") }
                }
            }.paperScreen().navigationTitle(account == nil ? "添加账户" : "编辑账户").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { if dirty { discard = true } else { dismiss() } } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(validation != nil) }
                }
                .onAppear {
                    guard !didSetup else { return }
                    if let account { name = account.name; icon = account.icon; type = account.type; balanceText = Calc.format(account.initialBalance) }
                    baseline = fingerprint; didSetup = true
                }
                .protectDraft(dirty, confirming: $discard) { dismiss() }
                .confirmationDialog(account?.isArchived == true ? "恢复账户？" : "归档账户？", isPresented: $archive, titleVisibility: .visible) {
                    Button(account?.isArchived == true ? "恢复账户" : "归档账户") {
                        guard let account else { return }
                        account.archived = !account.isArchived
                        do { try context.save(); session.saved(account.isArchived ? "账户已归档，历史账目已保留" : "账户已恢复"); dismiss() }
                        catch { context.rollback(); self.error = "操作失败，请重试。" }
                    }
                } message: { Text("不会删除账目或解除账户关联。已有订阅仍使用原账户，可在订阅管理中更改。") }
                .alert("未能保存", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("好") { error = nil }
                } message: { Text(error ?? "") }
        }
    }
    private func save() {
        guard validation == nil, let balance = Double(balanceText) else { return }
        if let account { account.name = cleanName; account.icon = icon; account.type = type; account.initialBalance = (balance * 100).rounded() / 100 }
        else { context.insert(AccountModel(name: cleanName, icon: icon, type: type, initialBalance: (balance * 100).rounded() / 100,
                                            sortOrder: (accounts.map(\.sortOrder).max() ?? -1) + 1)) }
        do { try context.save(); session.saved("账户已保存"); dismiss() }
        catch { context.rollback(); self.error = "输入已保留，请稍后重试。" }
    }
}
