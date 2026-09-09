import SwiftUI
import SwiftData

private struct EntryDraft: Codable {
    var amount: String; var type: String; var parent: String; var child: String
    var account: String?; var ledger: String; var note: String; var date: Date
    var installment: Bool; var periods: Int
}

struct TransactionEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var session: AppSession
    @Query(sort: \CategoryModel.sortOrder) private var categories: [CategoryModel]
    @Query(sort: \AccountModel.sortOrder) private var accounts: [AccountModel]
    @Query(sort: \TxRecord.createdAt, order: .reverse) private var records: [TxRecord]
    @Query private var ledgers: [LedgerModel]
    @AppStorage("selectedLedger") private var currentLedger = LedgerChoice.legacyKey
    @AppStorage("transactionDraft") private var draftRaw = ""
    var editing: TxRecord? = nil
    var initialDate: Date? = nil
    @State private var ledgerKey = LedgerChoice.legacyKey
    @State private var type: TransactionType = .expense
    @State private var amountText = ""
    @State private var selectedParent: CategoryModel?
    @State private var legacyChild = ""
    @State private var selectedChild: CategoryModel?
    @State private var selectedAccount: AccountModel?
    @State private var note = ""
    @State private var date = Date.now
    @State private var isInstallment = false
    @State private var periods = 3
    @State private var showCategories = false
    @State private var showKeypad = false
    @State private var didSetup = false
    @State private var baseline = ""
    @State private var confirmDiscard = false
    @State private var confirmDelete = false
    @State private var saveError: String?
    @State private var restoredDraft = false
    @State private var clearOnNextInput = false
    @FocusState private var noteFocused: Bool

    private var keepsLegacyCategory: Bool { editing != nil && selectedParent == nil && editing?.type == type }
    private var selectedName: String { selectedParent?.name ?? (keepsLegacyCategory ? editing?.categoryName ?? "未分类" : "选择分类") }
    private var draft: EntryDraft {
        EntryDraft(amount: amountText, type: type.rawValue, parent: selectedParent?.name ?? "", child: selectedChild?.name ?? legacyChild,
                   account: selectedAccount?.uid, ledger: ledgerKey, note: note, date: date,
                   installment: isInstallment, periods: periods)
    }
    private var fingerprint: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return (try? String(data: encoder.encode(draft), encoding: .utf8)) ?? ""
    }
    private var dirty: Bool { didSetup && fingerprint != baseline }
    private var validation: String? {
        if amountText.isEmpty { return "先输入金额，再选择分类。" }
        guard let total = Calc.evaluate(amountText), total.isFinite else { return "算式无法计算，请检查除数是否为 0。" }
        if amountText.last.map({ "+-×÷".contains($0) }) == true { return "请补全算式，或删除末尾的运算符。" }
        if (total * 100).rounded() < 1 { return "金额至少为 0.01 元。" }
        if total >= 1_000_000_000 { return "金额需小于 10 亿元。" }
        if selectedParent == nil && !keepsLegacyCategory { return "请选择这笔账的分类。" }
        if isInstallment && Int((total * 100).rounded()) < periods { return "总金额不足以分成 \(periods) 期，每期至少 0.01 元。" }
        return nil
    }
    private var topCategories: [CategoryModel] { categories.filter { $0.parent == nil && $0.type == type && !$0.isArchived } }
    private var recentCategories: [CategoryModel] {
        var names: [String] = []
        for record in records where !record.isTrashed && record.ledgerKey == ledgerKey && record.type == type {
            if !names.contains(record.categoryName) { names.append(record.categoryName) }
            if names.count == 4 { break }
        }
        let recent = names.compactMap { name in topCategories.first { $0.matches(name) } }
        return Array((recent + topCategories.filter { cat in !recent.contains(where: { $0 === cat }) }).prefix(4))
    }
    private var typeBinding: Binding<TransactionType> {
        Binding(get: { type }, set: { type = $0; selectedParent = nil; selectedChild = nil; legacyChild = "" })
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let landscape = geometry.size.width > 650 && geometry.size.height < 500
                let contentWidth = landscape && showKeypad ? geometry.size.width * 0.54 : geometry.size.width
                ScrollViewReader { reader in
                    HStack(alignment: .top, spacing: 0) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                if showKeypad && typeSize.isAccessibilitySize {
                                    accessibleAmountInput
                                } else {
                                Picker("收支类型", selection: typeBinding) {
                                    ForEach(TransactionType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                                }.pickerStyle(.segmented)
                                amountCard
                                categoryCard.id("category")
                                options
                                InlineValidation(message: validation)
                                if restoredDraft { Text("已恢复上次未完成的记账").font(.footnote).foregroundStyle(.secondary) }
                                }
                            }.frame(width: max(0, min(contentWidth, 640) - 40), alignment: .leading).padding(20).frame(width: contentWidth, alignment: .center)
                        }.frame(width: contentWidth).scrollDismissesKeyboard(.interactively)
                            .safeAreaInset(edge: .bottom, spacing: 0) {
                                if !landscape && showKeypad {
                                    keypad(maxHeight: geometry.size.height * (typeSize.isAccessibilitySize ? 0.74 : 0.54)) {
                                        closeKeypad(); reader.scrollTo("category", anchor: .top)
                                    }.frame(width: contentWidth)
                                } else if !showKeypad && !noteFocused {
                                    Button(action: save) { Text(editing == nil ? "完成记账" : "保存修改").frame(maxWidth: .infinity) }
                                        .buttonStyle(PrimaryButtonStyle()).disabled(validation != nil)
                                        .accessibilityIdentifier("saveTransactionBottom")
                                        .padding(.horizontal, 20).padding(.vertical, 10).background(PaperTheme.paper)
                                }
                            }
                        if landscape && showKeypad {
                            keypad(maxHeight: geometry.size.height) { closeKeypad(); reader.scrollTo("category", anchor: .top) }
                                .frame(width: geometry.size.width * 0.46)
                        }
                    }
                    .onChange(of: showKeypad) { _, visible in
                        if !visible { reader.scrollTo("category", anchor: .top) }
                    }
                }
            }
            .paperScreen().navigationTitle(editing == nil ? "记一笔" : "编辑账目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { if dirty { confirmDiscard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", action: save).fontWeight(.semibold).disabled(validation != nil)
                        .accessibilityIdentifier("saveTransaction")
                }
                if editing != nil {
                    ToolbarItem(placement: .bottomBar) { Button("删除这笔账", role: .destructive) { confirmDelete = true } }
                }
            }
            .sheet(isPresented: $showCategories) {
                CategoryChooser(type: type, selectedParent: Binding(get: { selectedParent }, set: { selectedParent = $0; legacyChild = "" }), selectedChild: Binding(get: { selectedChild }, set: { selectedChild = $0; legacyChild = "" }))
            }
            .protectDraft(dirty, confirming: $confirmDiscard) { if editing == nil { draftRaw = "" }; dismiss() }
            .confirmationDialog("将这笔账移到最近删除？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("移到最近删除", role: .destructive) { if let editing, session.delete([editing], in: context) { dismiss() } }
            } message: { Text("只处理当前这一笔，可在设置中恢复。其他分期不受影响。") }
            .alert("未能保存", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("好") { saveError = nil }
            } message: { Text(saveError ?? "") }
            .onAppear(perform: setup)
            .onChange(of: fingerprint) { _, _ in if editing == nil && didSetup && dirty { draftRaw = fingerprint } }
            .onChange(of: noteFocused) { _, focused in if focused { showKeypad = false } }
        }
    }
    private var accessibleAmountInput: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("金额").font(.caption)
                Spacer()
                Button("收起", action: closeKeypad).font(.caption).frame(minHeight: 44)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text("¥" + (amountText.isEmpty ? "0" : amountText))
                    .font(.system(.title2, design: .serif)).monospacedDigit().fixedSize()
            }
        }.padding(12).paperCard()
    }
    private var amountCard: some View {
        Button { noteFocused = false; showKeypad = true } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text("金额").font(.subheadline).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    Text("¥" + (amountText.isEmpty ? "0" : amountText))
                        .font(.system(.largeTitle, design: .serif)).monospacedDigit().fixedSize()
                }
                if amountText.contains(where: { "+-×÷".contains($0) }), let value = Calc.evaluate(amountText) {
                    Text("计算结果 \(value.asCurrency)").font(.footnote).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(18).paperCard()
                .overlay { RoundedRectangle(cornerRadius: 20).stroke(showKeypad ? PaperTheme.accent : .clear, lineWidth: 1.5) }
        }.buttonStyle(.plain).accessibilityLabel("金额")
            .accessibilityValue(amountText.isEmpty ? "尚未输入" : amountText)
            .accessibilityHint("点按继续编辑，已有数字会保留；可用清空重新输入。")
    }
    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { closeKeypad(); showCategories = true } label: {
                AdaptiveRow {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("分类").font(.caption).foregroundStyle(.secondary)
                        Text(selectedName + (selectedChild.map { " · " + $0.name } ?? "")).font(.headline)
                    }
                    AdaptiveSpacer()
                    Label("全部", systemImage: "chevron.right").font(.subheadline)
                }.frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("chooseCategory")
            if keepsLegacyCategory {
                Text("保留原分类。也可以从全部分类中重新选择。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 2 : 4)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(recentCategories) { cat in
                    let selected = selectedParent === cat
                    Button { selectedParent = cat; selectedChild = nil; legacyChild = ""; closeKeypad() } label: {
                        VStack(spacing: 6) {
                            CategoryGlyph(name: cat.name, icon: cat.icon, size: 36)
                            Text(cat.name).font(.caption).fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(selected ? PaperTheme.soft : .clear, in: RoundedRectangle(cornerRadius: 14))
                            .overlay { RoundedRectangle(cornerRadius: 14).stroke(selected ? PaperTheme.accent : .clear, lineWidth: 1) }
                    }.buttonStyle(.plain).accessibilityLabel(cat.name)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            if let parent = selectedParent, !parent.sortedChildren.filter({ !$0.isArchived }).isEmpty {
                AdaptiveRow { Text("子分类").accessibilityHidden(true); AdaptiveSpacer(); Picker("子分类", selection: Binding(get: { selectedChild?.uid ?? (legacyChild.isEmpty ? "" : "__legacy") }, set: { value in
                    selectedChild = parent.sortedChildren.first { $0.uid == value }; legacyChild = ""
                })) {
                    Text("不分子类").tag("")
                    if !legacyChild.isEmpty { Text(legacyChild + "（原子类）").tag("__legacy") }
                    ForEach(parent.sortedChildren.filter { !$0.isArchived || $0 === selectedChild }) { Text($0.name).tag($0.uid) }
                }.labelsHidden().pickerStyle(.menu).frame(minHeight: 44) }
            }
        }.padding(16).paperCard()
    }
    private var options: some View {
        VStack(alignment: .leading, spacing: 10) {
            AdaptiveRow { Text("账户").accessibilityHidden(true); AdaptiveSpacer(); Picker("账户", selection: Binding(get: { selectedAccount?.uid ?? "" }, set: { value in
                selectedAccount = accounts.first { $0.uid == value }
            })) {
                Text("不指定账户").tag("")
                ForEach(accounts.filter { !$0.isArchived || $0 === selectedAccount }) {
                    Text($0.name + ($0.isArchived ? "（已归档）" : "")).tag($0.uid)
                }
            }.labelsHidden().frame(minHeight: 44) }
            Divider()
            AdaptiveRow { Text("账本").accessibilityHidden(true); AdaptiveSpacer(); Picker("账本", selection: $ledgerKey) {
                ForEach(LedgerChoice.choices(ledgers)) { Text($0.name).tag($0.id) }
            }.labelsHidden().frame(minHeight: 44).accessibilityIdentifier("entryLedgerPicker") }
            Divider()
            DatePicker("日期", selection: $date, displayedComponents: [.date])
                .datePickerStyle(.compact).frame(minHeight: 44)
            if date > .now { Text("未来日期的账目会标记为计划，不计入当前账户余额。")
                .font(.footnote).foregroundStyle(.secondary) }
            Divider()
            TextField("备注（可不填）", text: $note, axis: .vertical).focused($noteFocused).frame(minHeight: 44)
            if editing == nil {
                Divider()
                Toggle("分期", isOn: $isInstallment).frame(minHeight: 44)
                if isInstallment {
                    Stepper("\(periods) 期", value: $periods, in: 2...60).frame(minHeight: 44)
                    Text("从所选日期开始，每月一笔。总金额按分分配，合计保持不变。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }.padding(16).paperCard()
    }
    private func keypad(maxHeight: CGFloat, next: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            if !typeSize.isAccessibilitySize {
                HStack {
                    Text("输入金额").font(.subheadline)
                    Spacer()
                    Button("收起", action: closeKeypad).frame(minHeight: 44)
                }.padding(.horizontal, 16)
            }
            CalculatorKeypad(text: $amountText, clearOnNextInput: $clearOnNextInput, onDone: next)
        }.frame(maxHeight: maxHeight).background(PaperTheme.paper)
            .overlay(alignment: .top) { Divider() }
            .transition(reduceMotion ? .opacity : .move(edge: .bottom))
    }
    private func closeKeypad() { showKeypad = false; noteFocused = false }
    private func setup() {
        guard !didSetup else { return }
        if let r = editing {
            type = r.type; amountText = Calc.format(r.amount); note = r.note; date = r.date
            selectedParent = categories.first { $0.parent == nil && $0.type == r.type && $0.matches(r.categoryName) }
            selectedChild = selectedParent?.sortedChildren.first { $0.matches(r.subcategoryName) }
            if selectedChild == nil { legacyChild = r.subcategoryName }
            selectedAccount = r.account; ledgerKey = r.ledgerKey
        } else {
            ledgerKey = currentLedger; selectedAccount = accounts.first { !$0.isArchived }
            date = initialDate ?? .now
            if let data = draftRaw.data(using: .utf8), let saved = try? JSONDecoder().decode(EntryDraft.self, from: data) {
                type = TransactionType(rawValue: saved.type) ?? .expense
                amountText = saved.amount; note = saved.note; date = saved.date; ledgerKey = saved.ledger
                selectedParent = categories.first { $0.parent == nil && $0.type == type && $0.matches(saved.parent) }
                selectedChild = selectedParent?.sortedChildren.first { $0.matches(saved.child) }
                if selectedChild == nil { legacyChild = saved.child }
                selectedAccount = accounts.first { $0.uid == saved.account }
                isInstallment = saved.installment; periods = saved.periods; restoredDraft = true
            }
            showKeypad = true
        }
        baseline = restoredDraft ? "" : fingerprint
        didSetup = true
    }
    private func save() {
        guard validation == nil, let value = Calc.evaluate(amountText) else { return }
        let total = (value * 100).rounded() / 100
        let parentName = selectedParent?.name ?? editing?.categoryName ?? ""
        let icon = selectedParent?.icon ?? editing?.categoryIcon ?? ""
        let child = selectedChild?.name ?? legacyChild
        var savedRecord: TxRecord?
        if let r = editing {
            r.amount = total; r.type = type; r.categoryName = parentName; r.categoryIcon = icon
            r.subcategoryName = child; r.note = note; r.date = date; r.account = selectedAccount; r.ledgerKey = ledgerKey
            savedRecord = r
        } else {
            let plan = isInstallment ? InstallmentPlan.amounts(total: total, periods: periods) : [total]
            guard !plan.isEmpty else { return }
            let group: UUID? = isInstallment ? UUID() : nil
            for (i, amount) in plan.enumerated() {
                let r = TxRecord(amount: amount, type: type, categoryName: parentName, categoryIcon: icon,
                                 subcategoryName: child, note: note,
                                 date: Calendar.current.date(byAdding: .month, value: i, to: date) ?? date,
                                 installmentGroupID: group, installmentIndex: i + 1, installmentCount: plan.count)
                r.account = selectedAccount; r.ledgerKey = ledgerKey; context.insert(r)
                if i == 0 { savedRecord = r }
            }
        }
        do {
            try context.save()
            currentLedger = ledgerKey; session.month = date; session.selection = 0
            session.selectedRecord = savedRecord?.persistentModelID
            if editing == nil { draftRaw = "" }
            session.saved(isInstallment ? "已保存 \(periods) 期 · 合计 \(total.asCurrency)" : "已保存 · \(total.asCurrency)")
            dismiss()
        } catch { context.rollback(); saveError = "输入已保留，请稍后重试。"; session.failed("这笔账尚未保存") }
    }
}

struct CategoryChooser: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CategoryModel.sortOrder) private var categories: [CategoryModel]
    let type: TransactionType
    @Binding var selectedParent: CategoryModel?
    @Binding var selectedChild: CategoryModel?
    @State private var search = ""
    @State private var managing = false
    var body: some View {
        NavigationStack {
            PaperList {
                ForEach(categories.filter { $0.parent == nil && $0.type == type && !$0.isArchived &&
                    (search.isEmpty || $0.name.localizedStandardContains(search) || $0.sortedChildren.contains { $0.name.localizedStandardContains(search) }) }) { parent in
                    Section {
                        Button { selectedParent = parent; selectedChild = nil; dismiss() } label: {
                            HStack { CategoryGlyph(name: parent.name, icon: parent.icon); Text(parent.name); Spacer()
                                if selectedParent === parent && selectedChild == nil { Image(systemName: "checkmark") }
                            }.frame(minHeight: 44)
                        }.accessibilityAddTraits(selectedParent === parent && selectedChild == nil ? .isSelected : [])
                        ForEach(parent.sortedChildren.filter { !$0.isArchived && (search.isEmpty || parent.name.localizedStandardContains(search) || $0.name.localizedStandardContains(search)) }) { child in
                            Button { selectedParent = parent; selectedChild = child; dismiss() } label: {
                                HStack { Text(child.name).padding(.leading, 54); Spacer()
                                    if selectedChild === child { Image(systemName: "checkmark") }
                                }.frame(minHeight: 44)
                            }.accessibilityAddTraits(selectedChild === child ? .isSelected : [])
                        }
                    }.listRowBackground(PaperTheme.surface)
                }
            }.searchable(text: $search, prompt: "搜索分类").paperScreen().navigationTitle("选择分类")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("返回") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) { Button("管理") { managing = true } }
                }.sheet(isPresented: $managing) { CategoryManagerView() }
        }
    }
}
