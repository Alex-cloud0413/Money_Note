//
//  ContentView.swift
//  MoneyNote
//
//  首页：顶部月度汇总卡片 + 按天分组的账单流水。
//  点 + 新建；点某一笔进入编辑；左上角进入分类管理。
//

import SwiftUI
import SwiftData
import CoreData

struct ContentView: View {
    @AppStorage("selectedLedger") private var ledgerKey = LedgerChoice.legacyKey
    @Query private var subscriptions: [SubscriptionModel]
    @State private var editingSubscription: SubscriptionModel?
    @Environment(\.modelContext) private var modelContext
    // 从数据库读出所有流水，按日期倒序（新的在上面）
    @Query(sort: \TxRecord.date, order: .reverse) private var transactions: [TxRecord]
    @Query(sort: \BudgetModel.sortOrder) private var budgets: [BudgetModel]

    @State private var month: Date = .now          // 当前查看的月份，默认当月
    @State private var showingAdd = false
    @State private var showingSettings = false
    @State private var editingRecord: TxRecord?
    @State private var maintenanceTask: Task<Void, Never>? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack { LedgerPicker(); Spacer() }.padding(.horizontal, 20)
                monthHeader
                PinnedCategoryCards(records: monthRecords)
                if monthRecords.isEmpty {
                    emptyView
                } else {
                    List {
                        Section {
                            MonthSummaryCard(expense: monthExpense, income: monthIncome)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)

                            if let tb = totalBudget {
                                BudgetProgressCard(title: "总预算", icon: "🎯",
                                                   spent: monthExpense, limit: tb.amount)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                                    .listRowBackground(Color.clear)
                            }
                        }

                        ForEach(sortedDays, id: \.self) { day in
                            Section {
                                ForEach(transactionsByDay[day] ?? []) { tx in
                                    Button {
                                        if tx.isSubscription, let sub = subscriptions.first(where: { $0.uid == tx.subscriptionUID }) {
                                            editingSubscription = sub
                                        } else { editingRecord = tx }
                                    } label: {
                                        TransactionRow(transaction: tx)
                                    }
                                    .buttonStyle(.plain)
                                    .listRowBackground(PaperTheme.surface.opacity(0.85))
                                }
                                .onDelete { offsets in delete(day: day, offsets: offsets) }
                            } header: {
                                DayHeader(day: day, total: dayTotal(day))
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.insetGrouped)
                    .contentMargins(.top, 0, for: .scrollContent)
                }
            }
            .paperScreen()
            .navigationTitle("轻账记")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape").accessibilityLabel("设置")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus").font(.title3).accessibilityLabel("记一笔").accessibilityIdentifier("addTransaction")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                TransactionEditor()
            }
            .sheet(item: $editingSubscription) { SubscriptionEditor(editing: $0) }
            .sheet(item: $editingRecord) { record in
                TransactionEditor(editing: record)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
        // 首次启动写入默认分类和默认账户，做一次去重，并补齐订阅平摊流水
        .task {
            CategoryModel.seedDefaultsIfNeeded(modelContext)
            AccountModel.seedDefaultsIfNeeded(modelContext)
            DataMaintenance.deduplicate(modelContext)
            SubscriptionEngine.sync(modelContext, upTo: month)
        }
        // 翻到未来月份时，按需把订阅平摊记录补到该月
        .onChange(of: month) { _, newMonth in
            if newMonth > .now {
                SubscriptionEngine.sync(modelContext, upTo: newMonth)
            }
        }
        // iCloud 同步把云端数据导入后，再清一次重复并同步订阅。
        // iCloud 初次导入会连续触发很多次通知，这里用防抖合并成停下来后只跑一次，避免卡主线程。
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)) { _ in
            maintenanceTask?.cancel()
            maintenanceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                DataMaintenance.deduplicate(modelContext)
                SubscriptionEngine.sync(modelContext, upTo: month)
            }
        }
    }

    // MARK: - 月份切换（可往未来翻）

    private var monthHeader: some View {
        MonthPicker(month: $month).padding(.horizontal, 16)
    }

    // MARK: - 空状态

    private var emptyView: some View {
        ContentUnavailableView {
            Label("本月还没有记账", systemImage: "yensign.circle")
        } description: {
            Text("点右上角的 + 记一笔，或左右切换月份")
        } actions: {
            Button("记一笔") { showingAdd = true }
                .buttonStyle(.borderedProminent).foregroundStyle(PaperTheme.onAccent)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - 分组与统计（只统计所选月份）

    /// 当月总预算（若设置了）
    private var totalBudget: BudgetModel? { budgets.first { $0.isTotal && $0.ledgerKey == ledgerKey } }

    /// 所选月份的流水
    private var monthRecords: [TxRecord] {
        transactions.filter {
            $0.ledgerKey == ledgerKey && Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month)
        }
    }

    private var transactionsByDay: [Date: [TxRecord]] {
        Dictionary(grouping: monthRecords) {
            Calendar.current.startOfDay(for: $0.date)
        }
    }

    private var sortedDays: [Date] {
        transactionsByDay.keys.sorted(by: >)
    }

    private func dayTotal(_ day: Date) -> Double {
        (transactionsByDay[day] ?? []).reduce(0) { $0 + $1.signedAmount }
    }

    private var monthExpense: Double {
        monthRecords.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
    }

    private var monthIncome: Double {
        monthRecords.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
    }

    // MARK: - 删除

    private func delete(day: Date, offsets: IndexSet) {
        let dayItems = transactionsByDay[day] ?? []
        for index in offsets {
            modelContext.delete(dayItems[index])
        }
    }
}

// MARK: - 本月汇总卡片

struct MonthSummaryCard: View {
    let expense: Double
    let income: Double
    var balance: Double { income - expense }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("本月结余").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "leaf").foregroundStyle(PaperTheme.accent)
            }
            Text(balance.asCurrency)
                .font(.system(size: 36, weight: .regular, design: .serif)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.65)
            Divider().overlay(PaperTheme.rule)
            HStack {
                summaryItem(title: "支出", value: expense)
                Spacer()
                summaryItem(title: "收入", value: income)
            }
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .paperCard().padding(.vertical, 8)
    }

    private func summaryItem(title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value.asCurrency).font(.headline).monospacedDigit()
        }
    }
}

// MARK: - 某天的分组标题

struct DayHeader: View {
    let day: Date
    let total: Double

    var body: some View {
        HStack {
            Text(day.asDayTitle)
            Spacer()
            Text(total >= 0 ? "结余 \(total.asCurrency)" : "支出 \((-total).asCurrency)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

// MARK: - 单条流水

struct TransactionRow: View {
    let transaction: TxRecord

    var body: some View {
        HStack(spacing: 12) {
            CategoryGlyph(name: transaction.categoryName)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(transaction.displayCategory)
                        .font(.body)
                    if transaction.isInstallment {
                        Text("分期 \(transaction.installmentIndex)/\(transaction.installmentCount)")
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(PaperTheme.soft))
                            .foregroundStyle(PaperTheme.accent)
                    }
                    if transaction.isSubscription {
                        Text("订阅")
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                if transaction.account != nil || !transaction.note.isEmpty {
                    HStack(spacing: 6) {
                        if let acc = transaction.account {
                            Text(acc.name)
                        }
                        if !transaction.note.isEmpty {
                            Text(transaction.note)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(transaction.type == .expense
                 ? "-\(transaction.amount.asCurrency)"
                 : "+\(transaction.amount.asCurrency)")
                .font(.system(.body, design: .rounded))
                .fontWeight(.medium)
                .foregroundStyle(transaction.type == .expense ? Color.primary : PaperTheme.accent)
        }
        .padding(.vertical, 2)
    }
}
