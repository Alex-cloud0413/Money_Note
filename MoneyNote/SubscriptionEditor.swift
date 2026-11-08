//
//  SubscriptionEditor.swift
//  MoneyNote
//
//  新增 / 编辑订阅。保存后立即触发 SubscriptionEngine.sync 生成或更新平摊流水。
//

import SwiftUI
import SwiftData

struct SubscriptionEditor: View {
    @EnvironmentObject private var session: AppSession
    @Query private var records: [TxRecord]
    @State private var baseline = ""
    @State private var discard = false
    @State private var showStopConfirm = false
    private var fingerprint: String {
        [name, cycle.rawValue, allocation.rawValue, currency.rawValue, String(amount ?? -1), String(hasPromo), String(firstAmount ?? -1),
         String(startDate.timeIntervalSince1970), selectedParent?.uid ?? "", selectedChild?.uid ?? "",
         ledgerKey, note, String(isActive)].joined(separator: "|")
    }
    private var keepsLegacyCategory: Bool { editing != nil && selectedParent == nil }
    private var affectedCount: Int { records.filter { $0.subscriptionUID == editing?.uid }.count }
    private var validation: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请填写订阅名称。" }
        guard let amount, amount.isFinite, amount < 1_000_000_000,
              currency.rounded(amount) >= 1 / currency.scale else { return "请填写有效的每期金额。" }
        if hasPromo {
            guard let firstAmount, firstAmount.isFinite, firstAmount >= 0, firstAmount < 1_000_000_000 else { return "首期优惠金额需为有效金额，可以为 0。" }
        }
        if selectedParent == nil && !keepsLegacyCategory { return "请选择分类。" }
        guard let converted = converted(amount) else { return "取得汇率后即可保存。" }
        if !converted.isFinite || converted < 0.01 || converted >= 1_000_000_000 {
            return "每期折合人民币需在 ¥0.01 至 10 亿元之间。"
        }
        if let firstAmount, hasPromo, let first = self.converted(firstAmount),
           !first.isFinite || first >= 1_000_000_000 {
            return "首期折合人民币需小于 10 亿元。"
        }
        return nil
    }
    @State private var saveError: String?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CategoryModel.sortOrder) private var allCategories: [CategoryModel]

    /// 传入要编辑的订阅；nil 表示新建
    var editing: SubscriptionModel? = nil
    @Query private var ledgers: [LedgerModel]
    @AppStorage("selectedLedger") private var currentLedger = LedgerChoice.legacyKey
    @State private var ledgerKey = LedgerChoice.legacyKey

    @State private var name = ""
    @State private var cycle: BillingCycle = .monthly
    @State private var allocation: AllocationUnit = .month
    @State private var currency: EntryCurrency = .CNY
    @StateObject private var fx = FXLookup()
    @State private var amount: Double? = nil
    @State private var hasPromo = false
    @State private var firstAmount: Double? = nil
    @State private var startDate = Date.now
    @State private var selectedParent: CategoryModel?
    @State private var legacyChild = ""
    @State private var selectedChild: CategoryModel?
    @State private var note = ""
    @State private var isActive = true
    @State private var didSetup = false
    @State private var showDeleteConfirm = false

    private var isEditing: Bool { editing != nil }

    private var expenseTopCategories: [CategoryModel] {
        allCategories.filter { $0.parent == nil && $0.type == .expense && (!$0.isArchived || $0 === selectedParent) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var quote: FXQuote? { fx.matching(currency, date: startDate) }

    private func converted(_ value: Double) -> Double? {
        currency == .CNY ? currency.rounded(value) : quote?.converted(value)
    }

    private var amortizedPreview: Double? {
        let count = allocation.count(start: startDate, months: cycle.months)
        guard let amount, amount.isFinite, amount > 0, let converted = converted(amount), count > 0 else { return nil }
        return converted / Double(count)
    }

    private var canSave: Bool { validation == nil }

    var body: some View {
        NavigationStack {
            PaperForm {
                Section("订阅") {
                    TextField("名称，如 爱奇艺会员", text: $name)
                }

                Section("续费") {
                    Picker("周期", selection: $cycle) {
                        ForEach(BillingCycle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    CurrencyPicker(currency: $currency)
                    Picker("平摊方式", selection: $allocation) {
                        ForEach(AllocationUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)

                    HStack {
                        Text("每期扣款")
                        Spacer()
                        TextField("0.00", value: $amount, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    DatePicker("首次开通日期", selection: $startDate, displayedComponents: .date)

                    Toggle("首期有优惠价", isOn: $hasPromo)
                    if hasPromo {
                        HStack {
                            Text("首期金额")
                            Spacer()
                            TextField("0.00", value: $firstAmount, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }

                    if currency != .CNY {
                        FXQuoteRow(quote: quote, amount: amount, failed: fx.failed, retry: fx.retry)
                        Text("订阅使用保存时确认的汇率计算各期平摊。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }

                    if let p = amortizedPreview {
                        HStack {
                            Text(allocation.averageLabel).foregroundStyle(.secondary)
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
                                selectedChild = nil; legacyChild = ""
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
                                Text(keepsLegacyCategory ? editing?.categoryName ?? "保留原分类" : "请选择").foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)

                    if let parent = selectedParent, !parent.sortedChildren.isEmpty {
                        Menu {
                            Button("不分") { selectedChild = nil; legacyChild = "" }
                            ForEach(parent.sortedChildren.filter { !$0.isArchived || $0 === selectedChild }) { child in
                                Button(child.name) { selectedChild = child; legacyChild = "" }
                            }
                        } label: {
                            HStack {
                                Text("子类")
                                Spacer()
                                Text(selectedChild?.name ?? (legacyChild.isEmpty ? "不分" : legacyChild)).foregroundStyle(selectedChild == nil ? .secondary : .primary)
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
                    HStack {
                        Text("备注")
                        TextField("可不填", text: $note)
                            .multilineTextAlignment(.trailing)
                    }

                    if isEditing {
                        Text(isActive ? "状态：进行中" : "状态：已停止").foregroundStyle(.secondary)
                    }
                }

                Section {
                    InlineValidation(message: validation)
                    Text(isEditing ? "保存订阅修改会更新它已生成的平摊账目。" : "订阅按所选方式平摊，计入所选账本的统计与预算。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if isEditing {
                    Section {
                        Button(isActive ? "停止订阅，保留历史账目" : "恢复订阅") { showStopConfirm = true }
                        Button("删除订阅及全部历史", role: .destructive) {
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
                    Button { if didSetup && fingerprint != baseline { discard = true } else { dismiss() } } label: { Label("取消", systemImage: "xmark") }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: { Label("保存", systemImage: "checkmark") }.disabled(!canSave)
                }
            }
            .confirmationDialog("删除订阅及 \(affectedCount) 笔账目？",
                                isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("永久删除订阅及其账目", role: .destructive) { deleteSubscription() }
            } message: { Text("此操作无法撤销。如果只是停止续费记账，请使用「停止订阅，保留历史账目」。") }
            .protectDraft(didSetup && fingerprint != baseline, confirming: $discard) { dismiss() }
            .confirmationDialog(isActive ? "停止生成新的订阅账目？" : "恢复订阅？", isPresented: $showStopConfirm, titleVisibility: .visible) {
                Button(isActive ? "停止并保留历史" : "恢复订阅") { isActive.toggle(); save() }
            } message: { Text(isActive ? "历史账目会保留，已生成的未来平摊计划会移除。" : "会按当前订阅设置补齐平摊账目。") }
            .onAppear(perform: setup)
            .task(id: fx.id(currency: currency, date: startDate)) {
                await fx.load(currency: currency, date: startDate)
            }
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
            let foreign = s.foreignAmount
            currency = foreign?.quote.currency ?? .CNY
            amount = foreign?.original ?? s.amount
            hasPromo = s.hasFirstPromo
            firstAmount = s.foreignFirstAmount ?? s.firstAmount
            startDate = s.startDate
            allocation = s.allocation
            fx.use(foreign?.quote, currency: currency, date: startDate)
            selectedParent = allCategories.first { $0.parent == nil && $0.type == .expense && $0.matches(s.categoryName) }
            selectedChild = selectedParent?.sortedChildren.first { $0.matches(s.subcategoryName) }
            if selectedChild == nil { legacyChild = s.subcategoryName }
            ledgerKey = s.ledgerKey
            note = s.note
            isActive = s.isActive
        } else {
            selectedParent = expenseTopCategories.first { $0.name == "其他" } ?? expenseTopCategories.first
            ledgerKey = currentLedger
        }
        baseline = fingerprint
    }

    // MARK: - 保存 / 删除

    private func save() {
        guard canSave, let original = amount, let amt = converted(original) else { return }
        let originalFirst = hasPromo ? (firstAmount ?? original) : original
        guard let firstAmt = converted(originalFirst) else { return }
        let foreign = quote.map { ForeignAmount(original: currency.rounded(original), quote: $0) }
        let parentName = selectedParent?.name ?? editing?.categoryName ?? ""
        let parentIcon = selectedParent?.icon ?? editing?.categoryIcon ?? ""
        let childName = selectedChild?.name ?? legacyChild
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        let sub: SubscriptionModel
        if let s = editing {
            sub = s
            s.name = trimmedName
            s.cycle = cycle
            s.amount = amt
            s.firstAmount = firstAmt
            s.startDate = startDate
            s.categoryName = parentName
            s.categoryIcon = parentIcon
            s.subcategoryName = childName
            s.ledgerKey = ledgerKey
            s.note = note
            s.isActive = isActive
        } else {
            sub = SubscriptionModel(name: trimmedName,
                                        cycle: cycle,
                                        amount: amt,
                                        firstAmount: firstAmt,
                                        startDate: startDate,
                                        categoryName: parentName,
                                        categoryIcon: parentIcon,
                                        subcategoryName: childName,
                                        note: note)
            sub.ledgerKey = ledgerKey
            modelContext.insert(sub)
        }

        sub.allocation = allocation
        sub.foreignAmount = foreign
        sub.foreignFirstAmount = foreign != nil && hasPromo ? currency.rounded(originalFirst) : nil

        do {
            try SubscriptionEngine.sync(modelContext, upTo: session.month, saving: false,
                                        rewriteAmounts: true, only: sub.uid)
            try modelContext.save()
            session.saved(isActive ? "订阅已保存" : "订阅已停止，历史账目已保留")
            dismiss()
        } catch {
            modelContext.rollback()
            saveError = "订阅尚未保存，请重试。"
        }
    }

    private func deleteSubscription() {
        guard let editing else { return }
        do {
            try SubscriptionEngine.deleteRecords(for: editing, in: modelContext)
            modelContext.delete(editing)
            try modelContext.save()
            session.saved("订阅及其历史账目已删除")
            dismiss()
        } catch { modelContext.rollback(); saveError = "删除失败，原账目已保留。" }
    }
}
