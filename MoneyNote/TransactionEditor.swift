//
//  TransactionEditor.swift
//  MoneyNote
//
//  「记一笔 / 编辑」合一的界面。
//  布局：所有选项（类型/金额/分类/子类/日期/备注/分期）平铺可滚动；
//  计算器键盘点金额时才从底部弹出，点「收起」收回。
//

import SwiftUI
import SwiftData

struct TransactionEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CategoryModel.sortOrder) private var allCategories: [CategoryModel]
    @Query(sort: \AccountModel.sortOrder) private var accounts: [AccountModel]

    /// 传入要编辑的记录；nil 表示新建
    var editing: TxRecord? = nil

    @State private var type: TransactionType = .expense
    @State private var amountText = ""
    @State private var selectedParent: CategoryModel?
    @State private var selectedChild: CategoryModel?
    @State private var selectedAccount: AccountModel?
    @State private var note = ""
    @State private var date = Date.now
    @State private var isInstallment = false
    @State private var periods = 3

    @State private var showManager = false
    @State private var showKeypad = false
    @State private var clearOnNextInput = false
    @State private var didSetup = false
    @FocusState private var noteFocused: Bool

    private var isEditing: Bool { editing != nil }

    private func topCategories(for type: TransactionType) -> [CategoryModel] {
        allCategories
            .filter { $0.parent == nil && $0.type == type }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// 切换收/支时同步重置选中分类
    private var typeBinding: Binding<TransactionType> {
        Binding(
            get: { type },
            set: { newType in
                type = newType
                selectedParent = topCategories(for: newType).first
                selectedChild = nil
            }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 16) {
                        Picker("类型", selection: typeBinding) {
                            ForEach(TransactionType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)

                        amountCard
                        categoryCard
                        optionCard
                    }
                    .padding()
                    .padding(.bottom, showKeypad ? 340 : 12)
                }
                .scrollDismissesKeyboard(.interactively)

                if showKeypad { keypadOverlay }
            }
            .navigationTitle(isEditing ? "编辑" : "记一笔")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                if isEditing {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("删除", role: .destructive) { deleteRecord() }
                    }
                }
            }
            .sheet(isPresented: $showManager) { CategoryManagerView() }
            .onAppear(perform: setup)
        }
    }

    // MARK: - 金额卡片（点击弹键盘）

    private var amountCard: some View {
        Button {
            noteFocused = false
            withAnimation { showKeypad = true }
        } label: {
            HStack {
                Text("金额").foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("¥" + (amountText.isEmpty ? "0" : amountText))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(amountText.isEmpty ? .secondary : .primary)
                    if amountText.contains(where: { "+-×÷".contains($0) }),
                       let v = Calc.evaluate(amountText) {
                        Text("= ¥\(Calc.format(v))")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(showKeypad ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 分类卡片（大类宫格 + 子类小标签）

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("分类").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button("管理分类") { showManager = true }.font(.subheadline)
            }
            let columns = Array(repeating: GridItem(.flexible()), count: 4)
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(topCategories(for: type)) { cat in
                    categoryCell(icon: cat.icon, name: cat.name,
                                 selected: cat.persistentModelID == selectedParent?.persistentModelID)
                        .onTapGesture {
                            selectedParent = cat
                            selectedChild = nil
                        }
                }
            }

            if let parent = selectedParent, !parent.sortedChildren.isEmpty {
                Divider()
                Text("子类（可不选）").font(.caption).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip(title: "不分", selected: selectedChild == nil) { selectedChild = nil }
                        ForEach(parent.sortedChildren) { child in
                            chip(title: child.name,
                                 selected: child.persistentModelID == selectedChild?.persistentModelID) {
                                selectedChild = child
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 日期 / 备注 / 分期

    private var optionCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("账户")
                Spacer()
                Menu {
                    ForEach(accounts) { acc in
                        Button { selectedAccount = acc } label: {
                            Text("\(acc.icon) \(acc.name)")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        if let acc = selectedAccount {
                            Text("\(acc.icon) \(acc.name)")
                        } else {
                            Text("选择账户").foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                }
            }
            .padding(.vertical, 8)
            Divider()
            DatePicker("日期", selection: $date, displayedComponents: [.date, .hourAndMinute])
                .padding(.vertical, 8)
            Divider()
            HStack {
                Text("备注")
                TextField("可不填", text: $note)
                    .multilineTextAlignment(.trailing)
                    .focused($noteFocused)
            }
            .padding(.vertical, 8)

            if !isEditing {
                Divider()
                Toggle("分期", isOn: $isInstallment.animation())
                    .padding(.vertical, 8)
                if isInstallment {
                    Divider()
                    Stepper("期数：\(periods) 期", value: $periods, in: 2...60)
                        .padding(.vertical, 8)
                    if let total = Calc.evaluate(amountText), total > 0 {
                        HStack {
                            Text("每期约").foregroundStyle(.secondary)
                            Spacer()
                            Text("¥\(Calc.format((total / Double(periods) * 100).rounded() / 100)) ，共 \(periods) 个月")
                                .foregroundStyle(.secondary)
                        }
                        .font(.footnote)
                        .padding(.bottom, 8)
                    }
                }
            }
        }
        .padding(.horizontal)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 计算器键盘浮层

    private var keypadOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                Text("¥" + (amountText.isEmpty ? "0" : amountText))
                    .font(.headline)
                Spacer()
                Button("收起") { withAnimation { showKeypad = false } }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color(.systemGroupedBackground))

            CalculatorKeypad(text: $amountText,
                             clearOnNextInput: $clearOnNextInput,
                             onDone: save)
        }
        .background(Color(.systemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 8, y: -2)
        .transition(.move(edge: .bottom))
    }

    // MARK: - 小组件

    private func categoryCell(icon: String, name: String, selected: Bool) -> some View {
        VStack(spacing: 6) {
            Text(icon).font(.title)
                .frame(width: 52, height: 52)
                .background(Circle().fill(selected ? Color.accentColor.opacity(0.2) : Color(.tertiarySystemBackground)))
                .overlay(Circle().stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
            Text(name).font(.caption)
                .foregroundStyle(selected ? Color.accentColor : .secondary)
        }
    }

    private func chip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(selected ? Color.accentColor : Color(.tertiarySystemBackground)))
                .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 初始化

    private func setup() {
        guard !didSetup else { return }
        didSetup = true
        if let r = editing {
            type = r.type
            amountText = Calc.format(r.amount)
            clearOnNextInput = true          // 编辑时按第一个数字键自动清空原金额
            note = r.note
            date = r.date
            selectedParent = topCategories(for: r.type).first { $0.name == r.categoryName }
            selectedChild = selectedParent?.sortedChildren.first { $0.name == r.subcategoryName }
            selectedAccount = r.account ?? accounts.first
        } else {
            selectedParent = topCategories(for: type).first
            selectedAccount = accounts.first
        }
    }

    // MARK: - 保存 / 删除

    private func save() {
        guard let parent = selectedParent else { return }
        guard let total = Calc.evaluate(amountText), total > 0 else { return }
        let pName = parent.name
        let icon = parent.icon
        let sName = selectedChild?.name ?? ""

        if let r = editing {
            r.amount = total
            r.type = type
            r.categoryName = pName
            r.categoryIcon = icon
            r.subcategoryName = sName
            r.note = note
            r.date = date
            r.account = selectedAccount
        } else if isInstallment && periods >= 2 {
            let group = UUID()
            let per = (total / Double(periods) * 100).rounded() / 100
            for i in 0..<periods {
                let amt = (i == periods - 1) ? (total - per * Double(periods - 1)) : per
                let d = Calendar.current.date(byAdding: .month, value: i, to: date) ?? date
                let rec = TxRecord(amount: amt, type: type,
                                   categoryName: pName, categoryIcon: icon, subcategoryName: sName,
                                   note: note, date: d,
                                   installmentGroupID: group, installmentIndex: i + 1, installmentCount: periods)
                rec.account = selectedAccount
                modelContext.insert(rec)
            }
        } else {
            let rec = TxRecord(amount: total, type: type,
                               categoryName: pName, categoryIcon: icon, subcategoryName: sName,
                               note: note, date: date)
            rec.account = selectedAccount
            modelContext.insert(rec)
        }
        dismiss()
    }

    private func deleteRecord() {
        if let r = editing { modelContext.delete(r) }
        dismiss()
    }
}
