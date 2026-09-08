//
//  AccountsView.swift
//  MoneyNote
//
//  账户页：总资产 + 各账户余额，可增删改。
//

import SwiftUI
import SwiftData

struct AccountsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AccountModel.sortOrder) private var accounts: [AccountModel]

    @State private var editing: AccountModel?
    @State private var adding = false

    private var netWorth: Double {
        accounts.reduce(0) { $0 + $1.balance }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 6) {
                        Text("净资产").font(.subheadline).foregroundStyle(.secondary)
                        Text(netWorth.asCurrency)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(netWorth < 0 ? PaperTheme.warning : PaperTheme.ink)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section {
                    ForEach(accounts) { acc in
                        Button {
                            editing = acc
                        } label: {
                            AccountRow(account: acc)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for i in offsets { modelContext.delete(accounts[i]) }
                    }

                    Button {
                        adding = true
                    } label: {
                        Label("添加账户", systemImage: "plus.circle.fill")
                    }
                }
            }
            .paperScreen()
            .navigationTitle("资金账户")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .sheet(item: $editing) { acc in
                AccountEditView(account: acc)
            }
            .sheet(isPresented: $adding) {
                AccountEditView(account: nil)
            }
        }
    }
}

/// 账户列表里的一行
struct AccountRow: View {
    let account: AccountModel

    var body: some View {
        HStack(spacing: 12) {
            CategoryGlyph(name: account.type.rawValue)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                Text(account.type.rawValue)
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(account.balance.asCurrency)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(account.balance < 0 ? PaperTheme.warning : PaperTheme.ink)
                if account.type == .credit && account.balance < 0 {
                    Text("欠款").font(.caption2).foregroundStyle(PaperTheme.warning)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// 新建 / 编辑账户
struct AccountEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \AccountModel.sortOrder) private var accounts: [AccountModel]

    var account: AccountModel?

    @State private var name = ""
    @State private var icon = "💵"
    @State private var type: AccountType = .cash
    @State private var balanceText = ""
    @State private var didSetup = false

    private var isEditing: Bool { account != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("图标")
                        Spacer()
                        TextField("emoji", text: $icon)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    HStack {
                        Text("名称")
                        TextField("如：招商银行", text: $name)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("类型", selection: $type) {
                        ForEach(AccountType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .onChange(of: type) { _, newType in
                        // 没自定义过图标时，跟随类型给默认图标
                        if icon.isEmpty { icon = newType.defaultIcon }
                    }
                }

                Section {
                    HStack {
                        Text("初始余额")
                        Spacer()
                        Text("¥")
                        TextField("0", text: $balanceText)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                    }
                } footer: {
                    Text("建账户时账上已有的钱。信用卡可填 0，已用额度填负数。")
                }
            }
            .paperScreen()
            .navigationTitle(isEditing ? "编辑账户" : "添加账户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if isEditing {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("删除", role: .destructive) { deleteAccount() }
                    }
                }
            }
            .onAppear(perform: setup)
        }
    }

    private func setup() {
        guard !didSetup else { return }
        didSetup = true
        if let a = account {
            name = a.name
            icon = a.icon
            type = a.type
            balanceText = Calc.format(a.initialBalance)
        }
    }

    private func save() {
        let balance = Double(balanceText) ?? 0
        let cleanIcon = icon.isEmpty ? type.defaultIcon : icon
        if let a = account {
            a.name = name
            a.icon = cleanIcon
            a.type = type
            a.initialBalance = balance
        } else {
            let order = (accounts.last?.sortOrder ?? -1) + 1
            let new = AccountModel(name: name, icon: cleanIcon, type: type,
                                   initialBalance: balance, sortOrder: order)
            modelContext.insert(new)
        }
        dismiss()
    }

    private func deleteAccount() {
        if let a = account { modelContext.delete(a) }
        dismiss()
    }
}
