import SwiftUI
import SwiftData

private struct EntryDraft: Codable {
    var amount: String
    var type: String
    var parent: String
    var child: String
    var ledger: String
    var note: String
    var date: Date
    var installment: Bool
    var periods: Int
}

private enum EntryStep: Int, CaseIterable {
    case amount
    case category
    case details

    var title: String {
        switch self {
        case .amount: return "金额"
        case .category: return "分类"
        case .details: return "详情"
        }
    }
}

struct TransactionEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var session: AppSession
    @Query(sort: \CategoryModel.sortOrder) private var categories: [CategoryModel]
    @Query private var ledgers: [LedgerModel]
    @AppStorage("selectedLedger") private var currentLedger = LedgerChoice.legacyKey
    @AppStorage("transactionDraft") private var draftRaw = ""

    var editing: TxRecord? = nil
    var initialDate: Date? = nil

    @State private var step: EntryStep = .amount
    @State private var direction = 1
    @State private var ledgerKey = LedgerChoice.legacyKey
    @State private var type: TransactionType = .expense
    @State private var amountText = ""
    @State private var selectedParent: CategoryModel?
    @State private var selectedChild: CategoryModel?
    @State private var legacyChild = ""
    @State private var childChoiceMade = false
    @State private var note = ""
    @State private var date = Date.now
    @State private var isInstallment = false
    @State private var periods = 3
    @State private var didSetup = false
    @State private var baseline = ""
    @State private var confirmDiscard = false
    @State private var confirmDelete = false
    @State private var saveError: String?
    @State private var restoredDraft = false
    @State private var clearOnNextInput = false
    @State private var managingCategories = false
    @State private var choosingChild = false
    @FocusState private var noteFocused: Bool

    private var keepsLegacyCategory: Bool {
        editing != nil && selectedParent == nil && editing?.type == type
    }
    private var activeChildren: [CategoryModel] {
        selectedParent?.sortedChildren.filter { !$0.isArchived || $0 === selectedChild } ?? []
    }
    private var selectedCategoryName: String {
        let parent = selectedParent?.name ?? (keepsLegacyCategory ? editing?.categoryName ?? "原分类" : "尚未选择")
        let child = selectedChild?.name ?? legacyChild
        return child.isEmpty ? parent : "\(parent) · \(child)"
    }
    private var topCategories: [CategoryModel] {
        categories.filter { $0.parent == nil && $0.type == type && !$0.isArchived }
    }
    private var draft: EntryDraft {
        EntryDraft(amount: amountText, type: type.rawValue,
                   parent: selectedParent?.name ?? "", child: selectedChild?.name ?? legacyChild,
                   ledger: ledgerKey, note: note, date: date,
                   installment: isInstallment, periods: periods)
    }
    private var fingerprint: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? String(data: encoder.encode(draft), encoding: .utf8)) ?? ""
    }
    private var dirty: Bool { didSetup && fingerprint != baseline }
    private var amountValue: Double? { Calc.evaluate(amountText) }
    private var amountValidation: String? {
        if amountText.isEmpty { return "请输入金额。" }
        guard let total = amountValue, total.isFinite else { return "算式无法计算，请检查除数是否为 0。" }
        if amountText.last.map({ "+-×÷".contains($0) }) == true { return "请补全算式，或删除末尾的运算符。" }
        if (total * 100).rounded() < 1 { return "金额至少为 0.01 元。" }
        if total >= 1_000_000_000 { return "金额需小于 10 亿元。" }
        return nil
    }
    private var categoryValidation: String? {
        if selectedParent == nil && !keepsLegacyCategory { return "请先选择一级分类。" }
        if !activeChildren.isEmpty && !childChoiceMade { return "请选择子分类，或选择「不分子类」。" }
        return nil
    }
    private var finalValidation: String? {
        if let amountValidation { return amountValidation }
        if let categoryValidation { return categoryValidation }
        if isInstallment, let total = amountValue, Int((total * 100).rounded()) < periods {
            return "总金额不足以分成 \(periods) 期，每期至少 0.01 元。"
        }
        return nil
    }
    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return direction > 0
            ? .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
            : .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                stepIndicator
                ZStack {
                    stepContent
                        .id(step)
                        .transition(stepTransition)
                }
                .clipped()
            }
            .paperScreen()
            .navigationTitle(editing == nil ? "记一笔 · \(step.title)" : "编辑账目 · \(step.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: cancel)
                        .accessibilityIdentifier("entryCancel")
                }
                if editing != nil && step == .details {
                    ToolbarItem(placement: .bottomBar) {
                        Button("删除这笔账", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .sheet(isPresented: $managingCategories) { CategoryManagerView() }
            .confirmationDialog(childDialogTitle, isPresented: $choosingChild,
                                titleVisibility: .visible) {
                Button("不分子类") { completeCategory(with: nil) }
                ForEach(activeChildren) { child in
                    Button(child.name) { completeCategory(with: child) }
                }
                Button("返回分类", role: .cancel) {}
            } message: {
                Text("选择后会自动进入详情。")
            }
            .protectDraft(dirty, confirming: $confirmDiscard) {
                if editing == nil { draftRaw = "" }
                dismiss()
            }
            .confirmationDialog("将这笔账移到最近删除？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("移到最近删除", role: .destructive) {
                    if let editing, session.delete([editing], in: context) { dismiss() }
                }
            } message: {
                Text("只处理当前这一笔，可在设置中恢复。其他分期不受影响。")
            }
            .alert("未能保存", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("好") { saveError = nil }
            } message: { Text(saveError ?? "") }
            .onAppear(perform: setup)
            .onChange(of: fingerprint) { _, _ in
                if editing == nil && didSetup && dirty { draftRaw = fingerprint }
            }
            .simultaneousGesture(previousStepSwipe)
        }
        .presentationDragIndicator(.visible)
    }

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(EntryStep.allCases, id: \.self) { item in
                HStack(spacing: 6) {
                    Text("\(item.rawValue + 1)")
                        .font(.caption.weight(.semibold))
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .frame(width: 28, height: 28)
                        .foregroundStyle(item.rawValue <= step.rawValue ? PaperTheme.onAccent : PaperTheme.ink)
                        .background(item.rawValue <= step.rawValue ? PaperTheme.accent : PaperTheme.soft, in: Circle())
                    if !typeSize.isAccessibilitySize { Text(item.title).font(.caption) }
                }
                if item != .details { Rectangle().fill(PaperTheme.rule).frame(height: 1) }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(step.rawValue + 1) 步，共 3 步，\(step.title)")
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case .amount: amountStep
        case .category: categoryStep
        case .details: detailsStep
        }
    }

    private var amountStep: some View {
        GeometryReader { geometry in
            if geometry.size.width > geometry.size.height {
                HStack(spacing: 0) {
                    amountOverview
                        .frame(width: max(320, geometry.size.width * 0.43))
                    Divider()
                    amountKeypad
                }
            } else {
                VStack(spacing: 0) {
                    amountOverview
                    amountKeypad
                        .frame(maxHeight: typeSize.isAccessibilitySize ? .infinity : 340)
                }
            }
        }
    }

    private var amountOverview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("先确定这笔账的类型与金额。")
                    .font(.subheadline).foregroundStyle(.secondary)
                Picker("收支类型", selection: Binding(get: { type }, set: { value in
                    type = value
                    selectedParent = nil
                    selectedChild = nil
                    legacyChild = ""
                    childChoiceMade = false
                })) {
                    ForEach(TransactionType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: 8) {
                    Text("金额").font(.subheadline).foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text("¥" + (amountText.isEmpty ? "0" : amountText))
                            .font(.system(.largeTitle, design: .serif)).monospacedDigit().fixedSize()
                    }
                    if amountText.contains(where: { "+-×÷".contains($0) }), let value = amountValue {
                        Text("计算结果 \(value.asCurrency)").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .paperCard()
                InlineValidation(message: amountText.isEmpty ? nil : amountValidation)
                if restoredDraft {
                    Text("已恢复上次未完成的记账")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .readableWidth()
        }
    }

    private var amountKeypad: some View {
        CalculatorKeypad(text: $amountText, clearOnNextInput: $clearOnNextInput,
                         canContinue: amountValidation == nil) {
            if amountValidation == nil { move(to: .category, forward: true) }
        }
        .overlay(alignment: .top) { Divider() }
    }

    private var categoryStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                stepSummary(title: type.rawValue, value: amountValue?.asCurrency ?? "¥0.00")
                Text("选择一级分类后，会自动显示它的子分类。")
                    .font(.subheadline).foregroundStyle(.secondary)
                let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: typeSize.isAccessibilitySize ? 2 : 3)
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(topCategories) { parent in
                        let selected = selectedParent === parent
                        Button {
                            choose(parent)
                        } label: {
                            VStack(spacing: 8) {
                                CategoryGlyph(name: parent.name, icon: parent.icon, size: 44)
                                Text(parent.name).font(.subheadline.weight(.medium)).lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, minHeight: 92)
                            .padding(8)
                            .background(selected ? PaperTheme.soft : PaperTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                            .overlay { RoundedRectangle(cornerRadius: 16).stroke(selected ? PaperTheme.accent : PaperTheme.rule, lineWidth: selected ? 1.5 : 0.5) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                if keepsLegacyCategory {
                    Button {
                        selectedParent = nil
                        selectedChild = nil
                        legacyChild = editing?.subcategoryName ?? ""
                        childChoiceMade = true
                        move(to: .details, forward: true)
                    } label: {
                        Label("保留原分类：\(selectedCategoryName)", systemImage: "clock.arrow.circlepath")
                            .frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
                InlineValidation(message: categoryValidation)
                Button { managingCategories = true } label: {
                    Label("管理分类", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity).frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .readableWidth()
        }
        .safeAreaInset(edge: .bottom) {
            stepFooter("下一步", canContinue: categoryValidation == nil,
                       identifier: "entryNext") {
                move(to: .details, forward: true)
            }
        }
    }

    private var detailsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(selectedCategoryName).font(.headline)
                    MoneyText(value: amountValue ?? 0, style: .title)
                    Text(type.rawValue).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .paperCard()

                VStack(alignment: .leading, spacing: 12) {
                    Picker("账本", selection: $ledgerKey) {
                        ForEach(LedgerChoice.choices(ledgers)) { Text($0.name).tag($0.id) }
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("entryLedgerPicker")
                    Divider()
                    DatePicker("日期", selection: $date, displayedComponents: [.date])
                        .datePickerStyle(.compact).frame(minHeight: 44)
                    if date > .now {
                        Text("未来日期会标记为计划，并计入所选月份的汇总与预算。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Divider()
                    TextField("备注（可不填）", text: $note, axis: .vertical)
                        .focused($noteFocused).frame(minHeight: 44)
                    if editing == nil {
                        Divider()
                        Toggle("分期", isOn: $isInstallment).frame(minHeight: 44)
                        if isInstallment {
                            Stepper("\(periods) 期", value: $periods, in: 2...60).frame(minHeight: 44)
                            Text("从所选日期开始，每月一笔。总金额按分分配，合计保持不变。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(16)
                .paperCard()
                InlineValidation(message: finalValidation)
            }
            .padding(20)
            .readableWidth()
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            stepFooter(editing == nil ? "完成记账" : "保存修改",
                       canContinue: finalValidation == nil,
                       identifier: "saveTransaction",
                       action: save)
        }
    }

    private var childDialogTitle: String {
        guard let selectedParent else { return "选择子分类" }
        return "\(selectedParent.name)的子分类"
    }

    private func choose(_ parent: CategoryModel) {
        selectedParent = parent
        selectedChild = nil
        legacyChild = ""
        childChoiceMade = false
        let children = parent.sortedChildren.filter { !$0.isArchived }
        if children.isEmpty {
            childChoiceMade = true
            move(to: .details, forward: true)
        } else {
            choosingChild = true
        }
    }

    private func completeCategory(with child: CategoryModel?) {
        selectedChild = child
        legacyChild = ""
        childChoiceMade = true
        choosingChild = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            guard step == .category else { return }
            move(to: .details, forward: true)
        }
    }

    private func stepSummary(title: String, value: String) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(.title3, design: .serif)).monospacedDigit()
        }
        .padding(16)
        .paperCard()
    }

    private func stepFooter(_ title: String, canContinue: Bool,
                            identifier: String, action: @escaping () -> Void) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                primaryStepButton(title, canContinue: canContinue,
                                  identifier: identifier, action: action)
                previousStepButton
            }
            VStack(alignment: .trailing, spacing: 8) {
                previousStepButton
                primaryStepButton(title, canContinue: canContinue,
                                  identifier: identifier, action: action)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(PaperTheme.paper)
    }

    private func primaryStepButton(_ title: String, canContinue: Bool,
                                   identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).frame(maxWidth: .infinity) }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canContinue)
            .accessibilityIdentifier(identifier)
    }

    private var previousStepButton: some View {
        Button(action: backOrCancel) {
            Label("上一步", systemImage: "chevron.left")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(minWidth: 88, minHeight: 48)
                .foregroundStyle(PaperTheme.ink)
                .background(PaperTheme.soft, in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(PaperTheme.rule, lineWidth: 0.5)
                }
                .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("entryBack")
        .accessibilityHint("也可以从左向右滑动返回")
    }

    private var previousStepSwipe: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onEnded { value in
                guard step != .amount else { return }
                let horizontal = value.translation.width
                let vertical = abs(value.translation.height)
                let projected = value.predictedEndTranslation.width
                guard horizontal > 56,
                      max(horizontal, projected) > 96,
                      horizontal > vertical * 1.4 else { return }
                backOrCancel()
            }
    }

    private func cancel() {
        if dirty { confirmDiscard = true } else { dismiss() }
    }

    private func backOrCancel() {
        switch step {
        case .amount:
            cancel()
        case .category:
            move(to: .amount, forward: false)
        case .details:
            noteFocused = false
            move(to: .category, forward: false)
        }
    }

    private func move(to newStep: EntryStep, forward: Bool) {
        direction = forward ? 1 : -1
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) { step = newStep }
    }

    private func setup() {
        guard !didSetup else { return }
        if let record = editing {
            type = record.type
            amountText = Calc.format(record.amount)
            note = record.note
            date = record.date
            selectedParent = categories.first { $0.parent == nil && $0.type == record.type && $0.matches(record.categoryName) }
            selectedChild = selectedParent?.sortedChildren.first { $0.matches(record.subcategoryName) }
            if selectedChild == nil { legacyChild = record.subcategoryName }
            childChoiceMade = true
            ledgerKey = record.ledgerKey
        } else {
            ledgerKey = currentLedger
            date = initialDate ?? .now
            if let data = draftRaw.data(using: .utf8), let saved = try? JSONDecoder().decode(EntryDraft.self, from: data) {
                type = TransactionType(rawValue: saved.type) ?? .expense
                amountText = saved.amount
                note = saved.note
                date = saved.date
                ledgerKey = saved.ledger
                selectedParent = categories.first { $0.parent == nil && $0.type == type && $0.matches(saved.parent) }
                selectedChild = selectedParent?.sortedChildren.first { $0.matches(saved.child) }
                if selectedChild == nil { legacyChild = saved.child }
                childChoiceMade = selectedParent != nil
                isInstallment = saved.installment
                periods = saved.periods
                restoredDraft = true
            }
        }
        baseline = restoredDraft ? "" : fingerprint
        didSetup = true
    }

    private func save() {
        guard finalValidation == nil, let value = amountValue else { return }
        let total = (value * 100).rounded() / 100
        let parentName = selectedParent?.name ?? editing?.categoryName ?? ""
        let icon = selectedParent?.icon ?? editing?.categoryIcon ?? ""
        let child = selectedChild?.name ?? legacyChild
        var savedRecord: TxRecord?

        if let record = editing {
            record.amount = total
            record.type = type
            record.categoryName = parentName
            record.categoryIcon = icon
            record.subcategoryName = child
            record.note = note
            record.date = date
            record.ledgerKey = ledgerKey
            savedRecord = record
        } else {
            let plan = isInstallment ? InstallmentPlan.amounts(total: total, periods: periods) : [total]
            guard !plan.isEmpty else { return }
            let group: UUID? = isInstallment ? UUID() : nil
            for (index, amount) in plan.enumerated() {
                let record = TxRecord(amount: amount, type: type,
                                      categoryName: parentName, categoryIcon: icon,
                                      subcategoryName: child, note: note,
                                      date: Calendar.current.date(byAdding: .month, value: index, to: date) ?? date,
                                      installmentGroupID: group, installmentIndex: index + 1,
                                      installmentCount: plan.count)
                record.ledgerKey = ledgerKey
                context.insert(record)
                if index == 0 { savedRecord = record }
            }
        }

        do {
            try context.save()
            currentLedger = ledgerKey
            session.month = date
            session.selection = 0
            session.selectedRecord = savedRecord?.persistentModelID
            if editing == nil { draftRaw = "" }
            session.saved(isInstallment ? "已保存 \(periods) 期 · 合计 \(total.asCurrency)" : "已保存 · \(total.asCurrency)")
            dismiss()
        } catch {
            context.rollback()
            saveError = "输入已保留，请稍后重试。"
            session.failed("这笔账尚未保存")
        }
    }
}
