import SwiftUI
import SwiftData

struct BudgetView: View {
    @EnvironmentObject private var session: AppSession
    @Query(sort: \BudgetModel.sortOrder) private var allBudgets: [BudgetModel]
    @Query private var transactions: [TxRecord]
    @AppStorage("selectedLedger") private var ledger = LedgerChoice.legacyKey
    @State private var editing: BudgetModel?
    @State private var addingTotal = false
    @State private var addingCategory = false
    private var budgets: [BudgetModel] { BudgetRules.effective(allBudgets, ledger: ledger, month: session.month) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LedgerPicker()
                    MonthPicker(month: $session.month)
                    if let total = budgets.first(where: \.isTotal) {
                        Button { editing = total } label: {
                            BudgetProgressCard(title: "总预算", icon: "circle.dashed", spent: spent(nil), limit: total.amount)
                        }.buttonStyle(.plain)
                    } else {
                        Button("设置本月总预算") { addingTotal = true }.buttonStyle(PrimaryButtonStyle())
                    }
                    HStack {
                        Text("分类预算").font(.headline); Spacer()
                        Button { addingCategory = true } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                            .accessibilityLabel("添加分类预算")
                    }
                    ForEach(budgets.filter { !$0.isTotal }) { budget in
                        Button { editing = budget } label: {
                            BudgetProgressCard(title: budget.categoryName, icon: "", spent: spent(budget.categoryName), limit: budget.amount)
                        }.buttonStyle(.plain)
                    }
                    Text("每个月的预算独立设置，修改当前月份不会影响其他月份。计划账目也计入所选月份的预算占用。")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(20).readableWidth()
            }.paperScreen().navigationTitle("预算").navigationBarTitleDisplayMode(.inline)
                .sheet(item: $editing) { BudgetEditView(budget: $0, month: session.month) }
                .sheet(isPresented: $addingTotal) { BudgetEditView(budget: nil, isTotalNew: true, month: session.month) }
                .sheet(isPresented: $addingCategory) { BudgetEditView(budget: nil, month: session.month) }
        }
    }
    private func spent(_ category: String?) -> Double {
        LedgerAnalytics.records(transactions, ledger: ledger, month: session.month, type: .expense, parent: category).reduce(0) { $0 + $1.amount }
    }
}

struct BudgetProgressCard: View {
    let title: String; let icon: String; let spent: Double; let limit: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AdaptiveRow {
                Text(title).font(.headline); AdaptiveSpacer()
                Text(spent > limit ? "超支 \((spent - limit).asCurrency)" : "剩余 \((limit - spent).asCurrency)")
                    .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
            ProgressView(value: min(max(spent, 0), max(limit, 0.01)), total: max(limit, 0.01))
                .tint(PaperTheme.accent).accessibilityLabel("预算使用进度")
                .accessibilityValue(limit > 0 ? "\(Int(spent / limit * 100))%" : "未设置")
            AdaptiveRow {
                Text("已计入 \(spent.asCurrency)"); AdaptiveSpacer(); Text("预算 \(limit.asCurrency)")
            }.font(.caption).foregroundStyle(.secondary)
        }.padding(18).paperCard()
    }
}

struct BudgetEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSession
    @AppStorage("selectedLedger") private var ledger = LedgerChoice.legacyKey
    @Query private var all: [BudgetModel]
    @Query(sort: \CategoryModel.sortOrder) private var categories: [CategoryModel]
    var budget: BudgetModel?
    var isTotalNew = false
    var month: Date = .now
    @State private var amountText = ""
    @State private var category = ""
    @State private var baseline = ""
    @State private var didSetup = false
    @State private var discard = false
    @State private var deleting = false
    @State private var error: String?
    private var isTotal: Bool { budget?.isTotal ?? isTotalNew }
    private var fingerprint: String { amountText + "|" + category }
    private var effective: [BudgetModel] { BudgetRules.effective(all, ledger: ledger, month: month) }
    private var available: [CategoryModel] {
        categories.filter { $0.parent == nil && $0.type == .expense && !$0.isArchived }
    }
    private var validation: String? {
        guard let amount = Double(amountText), amount.isFinite, amount > 0, amount < 1_000_000_000 else { return "预算需为 0.01 元至 10 亿元之间的有效金额。" }
        if (amount * 100).rounded() < 1 { return "预算至少为 0.01 元。" }
        if !isTotal && category.isEmpty { return "请选择分类。" }
        return nil
    }
    var body: some View {
        NavigationStack {
            PaperForm {
                if !isTotal {
                    Section("分类") {
                        if budget != nil { Text(category) }
                        else { Picker("分类", selection: $category) {
                            Text("请选择").tag("")
                            ForEach(available) { Text($0.name).tag($0.name) }
                        } }
                    }
                }
                Section("预算金额") {
                    TextField("金额", text: $amountText).keyboardType(.decimalPad)
                    InlineValidation(message: amountText.isEmpty ? nil : validation)
                }
                Section {
                    Text("只应用于 \(month.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "zh_CN"))))，其他月份保持原值。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if budget != nil {
                    Section { Button("删除本月设置", role: .destructive) { deleting = true } }
                }
            }.paperScreen().navigationTitle(isTotal ? "总预算" : "分类预算").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { if didSetup && fingerprint != baseline { discard = true } else { dismiss() } } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(validation != nil) }
                }
                .onAppear {
                    guard !didSetup else { return }
                    amountText = budget.map { Calc.format($0.amount) } ?? ""; category = budget?.categoryName ?? ""
                    baseline = fingerprint; didSetup = true
                }
                .protectDraft(didSetup && fingerprint != baseline, confirming: $discard) { dismiss() }
                .confirmationDialog("删除本月设置？", isPresented: $deleting, titleVisibility: .visible) {
                    Button("删除预算设置", role: .destructive) {
                        guard let budget else { return }
                        let old = BudgetModel(categoryName: budget.categoryName, amount: budget.amount, sortOrder: budget.sortOrder, ledgerKey: budget.ledgerKey)
                        old.monthKey = budget.monthKey
                        context.delete(budget)
                        do {
                            try context.save(); session.saved("预算设置已删除", undo: {
                                context.insert(old)
                                do { try context.save(); session.saved("预算设置已恢复") }
                                catch { context.rollback(); session.failed("恢复失败，请重试。") }
                            }); dismiss()
                        } catch { context.rollback(); self.error = "删除失败，请重试。" }
                    }
                } message: { Text("只删除当前月份的预算，账目和其他月份不会改变。") }
                .alert("未能保存", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("好") { error = nil }
                } message: { Text(error ?? "") }
        }
    }
    private func save() {
        guard validation == nil, let value = Double(amountText) else { return }
        let key = SubscriptionEngine.monthKey(month)
        let name = isTotal ? "" : category
        if let existing = all.first(where: { $0.ledgerKey == ledger && $0.categoryName == name && $0.monthKey == key }) {
            existing.amount = (value * 100).rounded() / 100
        } else {
            let new = BudgetModel(categoryName: name, amount: (value * 100).rounded() / 100, sortOrder: isTotal ? -1 : (all.map(\.sortOrder).max() ?? 0) + 1, ledgerKey: ledger)
            new.monthKey = key; context.insert(new)
        }
        do { try context.save(); session.saved("所选月份预算已保存"); dismiss() }
        catch { context.rollback(); self.error = "输入已保留，请稍后重试。" }
    }
}
