//
//  SubscriptionEditor.swift
//  MoneyNote
//
//  新增 / 编辑订阅。保存后立即触发 SubscriptionEngine.sync 生成或更新平摊流水。
//

import SwiftUI
import SwiftData

struct SubscriptionEditor: View {
    @State private var saveError: String?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CategoryModel.sortOrder) private var allCategories: [CategoryModel]
    @Query(sort: \AccountModel.sortOrder) private var accounts: [AccountModel]

    /// 传入要编辑的订阅；nil 表示新建
    var editing: SubscriptionModel? = nil
    @Query private var ledgers: [LedgerModel]
    @AppStorage("selectedLedger") private var currentLedger = LedgerChoice.legacyKey
    @State private var ledgerKey = LedgerChoice.legacyKey

    @State private var name = ""
    @State private var cycle: BillingCycle = .monthly
    @State private var amount: Double? = nil
    @State private var hasPromo = false
    @State private var firstAmount: Double? = nil
    @State private var startDate = Date.now
    @State private var selectedParent: CategoryModel?
    @State private var selectedChild: CategoryModel?
    @State private var selectedAccount: AccountModel?
    @State private var note = ""
    @State private var isActive = true
    @State private var didSetup = false
    @State private var showDeleteConfirm = false

    private var isEditing: Bool { editing != nil }

    private var expenseTopCategories: [CategoryModel] {
        allCategories.filter { $0.parent == nil && $0.type == .expense }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// 实时每月平摊预览
    private var amortizedPreview: Double? {
        guard let a = amount, a > 0 else { return nil }
        return ((a / Double(cycle.months)) * 100).rounded() / 100
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && (amount ?? 0) > 0
            && selectedParent != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("订阅") {
                    TextField("名称，如 爱奇艺会员", text: $name)
                }

                Section("续费") {
                    Picker("周期", selection: $cycle) {
                        ForEach(BillingCycle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("每期扣款")
                        Spacer()
                        TextField("0.00", value: $amount, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    DatePicker("首次开通日期", selection: $startDate, displayedComponents: .date)

                    Toggle("首期有优惠价", isOn: $hasPromo.animation())
                    if hasPromo {
                        HStack {
                            Text("首期金额")
                            Spacer()
                            TextField("0.00", value: $firstAmount, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }

                    if let p = amortizedPreview {
                        HStack {
                            Text("每月平摊约").foregroundStyle(.secondary)
                            Spacer()
                            Text(p.asCurrency).foregroundStyle(Color.accentColor)
                        }
                        .font(.subheadline)
                    }
                }

                Section("计入分类") {
                    Menu {
                        ForEach(expenseTopCategories) { cat in
                            Button {
                                selectedParent = cat
                                selectedChild = nil
                            } label: {
                                Text(cat.name)
                            }
                        }
                    } label: {
                        HStack {
                            Text("大类")
                            Spacer()
                            if let p = selectedParent {
                                Text(p.name)
                            } else {
                                Text("请选择").foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)

                    if let parent = selectedParent, !parent.sortedChildren.isEmpty {
                        Menu {
                            Button("不分") { selectedChild = nil }
                            ForEach(parent.sortedChildren) { child in
                                Button(child.name) { selectedChild = child }
                            }
                        } label: {
                            HStack {
                                Text("子类")
                                Spacer()
                                Text(selectedChild?.name ?? "不分").foregroundStyle(selectedChild == nil ? .secondary : .primary)
                                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }

                Section("其他") {
                    Picker("账本", selection: $ledgerKey) {
                        ForEach(LedgerChoice.choices(ledgers)) { Text($0.name).tag($0.id) }
                    }
                    Menu {
                        Button("不指定账户") { selectedAccount = nil }
                        ForEach(accounts) { acc in
                            Button { selectedAccount = acc } label: {
                                Text(acc.name)
                            }
                        }
                    } label: {
                        HStack {
                            Text("扣款账户")
                            Spacer()
                            if let acc = selectedAccount {
                                Text(acc.name)
                            } else {
                                Text("不指定").foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)

                    HStack {
                        Text("备注")
                        TextField("可不填", text: $note)
                            .multilineTextAlignment(.trailing)
                    }

                    if isEditing {
                        Toggle("仍在订阅中", isOn: $isActive)
                    }
                }

                if isEditing {
                    Section {
                        Button("删除订阅", role: .destructive) {
                            showDeleteConfirm = true
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .paperScreen()
            .navigationTitle(isEditing ? "编辑订阅" : "添加订阅")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(!canSave)
                }
            }
            .confirmationDialog("删除后会一并删除该订阅自动生成的所有流水，确定吗？",
                                isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("删除订阅及其流水", role: .destructive) { deleteSubscription() }
            }
            .onAppear(perform: setup)
            .alert("未能保存", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("好") { saveError = nil }
            } message: { Text(saveError ?? "") }
        }
    }

    // MARK: - 初始化

    private func setup() {
        guard !didSetup else { return }
        didSetup = true
        if let s = editing {
            name = s.name
            cycle = s.cycle
            amount = s.amount
            hasPromo = s.hasFirstPromo
            firstAmount = s.firstAmount
            startDate = s.startDate
            selectedParent = expenseTopCategories.first { $0.name == s.categoryName }
            selectedChild = selectedParent?.sortedChildren.first { $0.name == s.subcategoryName }
            selectedAccount = s.account
            ledgerKey = s.ledgerKey
            note = s.note
            isActive = s.isActive
        } else {
            selectedParent = expenseTopCategories.first { $0.name == "其他" } ?? expenseTopCategories.first
            selectedAccount = accounts.first
            ledgerKey = currentLedger
        }
    }

    // MARK: - 保存 / 删除

    private func save() {
        guard let parent = selectedParent, let amt = amount, amt > 0 else { return }
        let firstAmt = hasPromo ? (firstAmount ?? amt) : amt
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        if let s = editing {
            s.name = trimmedName
            s.cycle = cycle
            s.amount = amt
            s.firstAmount = firstAmt
            s.startDate = startDate
            s.categoryName = parent.name
            s.categoryIcon = parent.icon
            s.subcategoryName = selectedChild?.name ?? ""
            s.account = selectedAccount
            s.ledgerKey = ledgerKey
            s.note = note
            s.isActive = isActive
        } else {
            let sub = SubscriptionModel(name: trimmedName,
                                        cycle: cycle,
                                        amount: amt,
                                        firstAmount: firstAmt,
                                        startDate: startDate,
                                        categoryName: parent.name,
                                        categoryIcon: parent.icon,
                                        subcategoryName: selectedChild?.name ?? "",
                                        note: note)
            sub.account = selectedAccount
            sub.ledgerKey = ledgerKey
            modelContext.insert(sub)
        }

        do {
            try modelContext.save()
            SubscriptionEngine.sync(modelContext)
            dismiss()
        } catch {
            modelContext.rollback()
            saveError = "订阅尚未保存，请重试。"
        }
    }

    private func deleteSubscription() {
        if let s = editing {
            SubscriptionEngine.deleteRecords(for: s, in: modelContext)
            modelContext.delete(s)
        }
        dismiss()
    }
}
