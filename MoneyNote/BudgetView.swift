//
//  BudgetView.swift
//  MoneyNote
//
//  预算页：月份切换 + 总预算进度 + 各分类预算进度，超支标红。
//

import SwiftUI
import SwiftData

struct BudgetView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BudgetModel.sortOrder) private var allBudgets: [BudgetModel]
    @AppStorage("selectedLedger") private var ledgerKey = LedgerChoice.legacyKey
    private var budgets: [BudgetModel] { allBudgets.filter { $0.ledgerKey == ledgerKey } }
    @Query private var transactions: [TxRecord]
    @Query(sort: \CategoryModel.sortOrder) private var categories: [CategoryModel]

    @State private var month: Date = .now
    @State private var editing: BudgetModel?
    @State private var addingTotal = false
    @State private var addingCategory = false

    private var totalBudget: BudgetModel? { budgets.first { $0.isTotal } }
    private var categoryBudgets: [BudgetModel] { budgets.filter { !$0.isTotal } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack { LedgerPicker(); Spacer() }
                    monthHeader

                    // 总预算
                    if let tb = totalBudget {
                        Button { editing = tb } label: {
                            BudgetProgressCard(title: "本月总预算",
                                               icon: "🎯",
                                               spent: monthExpense(category: nil),
                                               limit: tb.amount)
                        }
                        .buttonStyle(.plain)
                    } else {
                        addButton(title: "设置总预算") { addingTotal = true }
                    }

                    // 分类预算
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("分类预算").font(.subheadline).foregroundStyle(.secondary)
                            Spacer()
                            Button { addingCategory = true } label: {
                                Image(systemName: "plus.circle.fill")
                            }
                        }
                        if categoryBudgets.isEmpty {
                            Text("还没有分类预算，点右上 + 添加")
                                .font(.footnote).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(categoryBudgets) { b in
                                Button { editing = b } label: {
                                    BudgetProgressCard(title: b.categoryName,
                                                       icon: iconFor(b.categoryName),
                                                       spent: monthExpense(category: b.categoryName),
                                                       limit: b.amount)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding()
            }
            .paperScreen()
            .navigationTitle("预算")
            .sheet(item: $editing) { b in
                BudgetEditView(budget: b)
            }
            .sheet(isPresented: $addingTotal) {
                BudgetEditView(budget: nil, isTotalNew: true)
            }
            .sheet(isPresented: $addingCategory) {
                BudgetEditView(budget: nil, isTotalNew: false)
            }
        }
    }

    // MARK: - 月份切换

    private var monthHeader: some View {
        HStack {
            Button { changeMonth(-1) } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 32)
            }
            Spacer()
            Text(monthTitle(month)).font(.headline)
            Spacer()
            Button { changeMonth(1) } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 32)
            }
        }
    }

    private func addButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: "plus.circle.fill")
                .frame(maxWidth: .infinity)
                .padding()
                .background(PaperTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - 计算

    private func monthExpense(category: String?) -> Double {
        transactions.filter {
            $0.ledgerKey == ledgerKey && $0.type == .expense &&
            Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) &&
            (category == nil || $0.categoryName == category)
        }
        .reduce(0) { $0 + $1.amount }
    }

    private func iconFor(_ name: String) -> String {
        categories.first { $0.parent == nil && $0.name == name }?.icon ?? "💸"
    }

    private func changeMonth(_ delta: Int) {
        if let m = Calendar.current.date(byAdding: .month, value: delta, to: month) {
            month = m
        }
    }

    private func monthTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月"
        return f.string(from: date)
    }
}

// MARK: - 预算进度卡片

struct BudgetProgressCard: View {
    let title: String
    let icon: String
    let spent: Double
    let limit: Double

    private var remaining: Double { limit - spent }
    private var ratio: Double { limit > 0 ? spent / limit : 0 }
    private var over: Bool { spent > limit }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: title.contains("预算") ? "circle.dashed" : PaperTheme.symbol(title))
                Spacer()
                Text(over ? "超支 \((-remaining).asCurrency)" : "剩 \(remaining.asCurrency)")
                    .font(.subheadline)
                    .foregroundStyle(over ? PaperTheme.warning : Color.secondary)
            }

            // 进度条
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(PaperTheme.soft).frame(height: 8)
                    Capsule()
                        .fill(over ? PaperTheme.warning : Color.accentColor)
                        .frame(width: geo.size.width * min(ratio, 1), height: 8)
                }
            }
            .frame(height: 8)

            HStack {
                Text("已花 \(spent.asCurrency)")
                Spacer()
                Text("预算 \(limit.asCurrency)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(PaperTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - 新建 / 编辑预算

struct BudgetEditView: View {
    @State private var saveError: String?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \BudgetModel.sortOrder) private var allBudgets: [BudgetModel]
    @AppStorage("selectedLedger") private var ledgerKey = LedgerChoice.legacyKey
    private var budgets: [BudgetModel] { allBudgets.filter { $0.ledgerKey == ledgerKey } }
    @Query(sort: \CategoryModel.sortOrder) private var categories: [CategoryModel]

    var budget: BudgetModel?
    var isTotalNew: Bool = false

    @State private var amountText = ""
    @State private var selectedCategory = ""
    @State private var didSetup = false

    private var isEditing: Bool { budget != nil }
    private var isTotal: Bool { budget?.isTotal ?? isTotalNew }

    /// 还没设过预算的支出大类（用于新建分类预算时选择）
    private var availableCategories: [CategoryModel] {
        let used = Set(budgets.map { $0.categoryName })
        return categories.filter { $0.parent == nil && $0.type == .expense && !used.contains($0.name) }
    }

    var body: some View {
        NavigationStack {
            Form {
                if !isTotal {
                    Section("分类") {
                        if isEditing {
                            Text(budget?.categoryName ?? "")
                        } else if availableCategories.isEmpty {
                            Text("所有分类都已设预算").foregroundStyle(.secondary)
                        } else {
                            Picker("分类", selection: $selectedCategory) {
                                ForEach(availableCategories) { c in
                                    Text(c.name).tag(c.name)
                                }
                            }
                        }
                    }
                }

                Section("每月预算金额") {
                    HStack {
                        Text("¥")
                        TextField("0", text: $amountText)
                            .keyboardType(.decimalPad)
                    }
                }

                if isEditing {
                    Section {
                        Button("删除预算", role: .destructive) { deleteBudget() }
                    }
                }
            }
            .paperScreen()
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: setup)
            .alert("未能保存", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("好") { saveError = nil }
            } message: { Text(saveError ?? "") }
        }
    }

    private var titleText: String {
        if isEditing { return "编辑预算" }
        return isTotal ? "设置总预算" : "添加分类预算"
    }

    private var canSave: Bool {
        guard let v = Double(amountText), v > 0 else { return false }
        if !isTotal && !isEditing && selectedCategory.isEmpty { return false }
        return true
    }

    private func setup() {
        guard !didSetup else { return }
        didSetup = true
        if let b = budget {
            amountText = Calc.format(b.amount)
        } else if !isTotal {
            selectedCategory = availableCategories.first?.name ?? ""
        }
    }

    private func save() {
        guard let amount = Double(amountText), amount > 0 else { return }
        if let b = budget {
            b.amount = amount
        } else if isTotal {
            modelContext.insert(BudgetModel(categoryName: "", amount: amount, sortOrder: -1, ledgerKey: ledgerKey))
        } else {
            guard !selectedCategory.isEmpty else { return }
            let order = (budgets.map { $0.sortOrder }.max() ?? 0) + 1
            modelContext.insert(BudgetModel(categoryName: selectedCategory, amount: amount, sortOrder: order, ledgerKey: ledgerKey))
        }
        do { try modelContext.save(); dismiss() } catch { modelContext.rollback(); saveError = "预算尚未保存，请重试。" }
    }

    private func deleteBudget() {
        if let b = budget { modelContext.delete(b) }
        dismiss()
    }
}
