import SwiftUI
import SwiftData
import CoreData
import Combine

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("selectedLedger") private var ledger = LedgerChoice.legacyKey
    @Query(sort: \TxRecord.date, order: .reverse) private var transactions: [TxRecord]
    @Query private var subscriptions: [SubscriptionModel]
    @Query private var budgets: [BudgetModel]
    @State private var showingAdd = false
    @State private var showingSettings = false
    @State private var editingRecord: TxRecord?
    @State private var editingSubscription: SubscriptionModel?
    @State private var maintenanceTask: Task<Void, Never>?
    private var records: [TxRecord] { LedgerAnalytics.records(transactions, ledger: ledger, month: session.month) }
    private var expense: Double { records.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount } }
    private var income: Double { records.filter { $0.type == .income }.reduce(0) { $0 + $1.amount } }
    private var planned: [TxRecord] { records.filter { $0.date > .now } }
    private var byDay: [Date: [TxRecord]] { Dictionary(grouping: records) { Calendar.current.startOfDay(for: $0.date) } }
    private var initialDate: Date {
        if Calendar.current.isDate(session.month, equalTo: .now, toGranularity: .month) { return .now }
        var parts = Calendar.current.dateComponents([.year, .month], from: session.month)
        parts.day = min(Calendar.current.component(.day, from: .now), Calendar.current.range(of: .day, in: .month, for: session.month)?.count ?? 28)
        parts.hour = 12
        return Calendar.current.date(from: parts) ?? session.month
    }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let wide = geometry.size.width >= 800 && !typeSize.isAccessibilitySize
                VStack(spacing: 0) {
                    AdaptiveRow { LedgerPicker(); AdaptiveSpacer(); MonthPicker(month: $session.month).frame(maxWidth: 350) }
                        .padding(.horizontal, 20)
                    if wide {
                        HStack(alignment: .top, spacing: 4) {
                            ScrollView { summary.padding(20) }.frame(width: min(380, geometry.size.width * 0.34))
                            recordList(includeSummary: false)
                        }
                    } else { recordList(includeSummary: true) }
                }.readableWidth(1200)
            }.paperScreen().navigationTitle("轻账记").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showingSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("设置")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingAdd = true } label: { Label("记一笔", systemImage: "plus") }
                            .accessibilityIdentifier("addTransaction")
                    }
                }
                .sheet(isPresented: $showingAdd) { TransactionEditor(initialDate: initialDate) }
                .sheet(item: $editingRecord) { TransactionEditor(editing: $0) }
                .sheet(item: $editingSubscription) { SubscriptionEditor(editing: $0) }
                .sheet(isPresented: $showingSettings) { SettingsView() }
        }
        .task { maintain() }
        .onChange(of: session.month) { _, month in sync(upTo: month) }
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)
            .receive(on: RunLoop.main)) { _ in
            maintenanceTask?.cancel()
            maintenanceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                maintain()
            }
        }
    }
    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonthSummaryCard(expense: expense, income: income)
            if !planned.isEmpty {
                Text("包含 \(planned.count) 笔计划账目，已计入所选月份的汇总与预算。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let budget = BudgetRules.effective(budgets, ledger: ledger, month: session.month).first(where: { $0.isTotal }) {
                BudgetProgressCard(title: "总预算", icon: "circle.dashed", spent: expense, limit: budget.amount)
            }
            PinnedCategoryCards(records: records)
        }
    }
    private func recordList(includeSummary: Bool) -> some View {
        ScrollViewReader { reader in
            PaperList {
                if includeSummary {
                    Section { summary.listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
                }
                if records.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("所选月份还没有账目", systemImage: "yensign.circle")
                        } description: { Text("新账会默认记在上方所选月份。") } actions: {
                            Button("记一笔") { showingAdd = true }.buttonStyle(PrimaryButtonStyle())
                        }.listRowBackground(Color.clear)
                    }
                }
                ForEach(byDay.keys.sorted(by: >), id: \.self) { day in
                    Section {
                        ForEach(byDay[day] ?? []) { record in
                            Button { edit(record) } label: { TransactionRow(transaction: record) }
                                .buttonStyle(.plain).listRowBackground(PaperTheme.surface)
                                .id(record.persistentModelID)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if record.isSubscription {
                                        Button("管理订阅") { edit(record) }.tint(PaperTheme.accent)
                                    } else {
                                        Button("删除", role: .destructive) { session.delete([record], in: context) }
                                    }
                                }
                        }
                    } header: {
                        DayHeader(day: day, total: (byDay[day] ?? []).reduce(0) { $0 + $1.signedAmount })
                    }
                }
            }.listStyle(.insetGrouped).scrollContentBackground(.hidden)
                .contentMargins(.top, 8, for: .scrollContent)
                .onChange(of: session.selectedRecord) { _, record in
                    if let record { reader.scrollTo(record, anchor: .center) }
                }
        }
    }
    private func edit(_ record: TxRecord) {
        if record.isSubscription, let sub = subscriptions.first(where: { $0.uid == record.subscriptionUID }) {
            editingSubscription = sub
        } else { editingRecord = record }
    }
    private func maintain() {
        do {
            try CategoryModel.seedDefaultsIfNeeded(context)
            try DataMaintenance.deduplicate(context)
            try SubscriptionEngine.sync(context, upTo: session.month)
        }
        catch { context.rollback(); session.failed("账目整理尚未完成，请稍后重新打开 App。") }
    }
    private func sync(upTo date: Date) {
        do { try SubscriptionEngine.sync(context, upTo: date) }
        catch { context.rollback(); session.failed("订阅平摊尚未更新，请稍后重试。") }
    }
}

struct MonthSummaryCard: View {
    let expense: Double
    let income: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("所选月份结余").font(.subheadline).foregroundStyle(.secondary)
            MoneyText(value: income - expense, style: .largeTitle)
            Divider()
            AdaptiveRow {
                item("支出", expense)
                AdaptiveSpacer()
                item("收入", income)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).paperCard()
    }
    private func item(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            MoneyText(value: value, style: .headline)
        }
    }
}

struct MoneyText: View {
    let value: Double
    var style: Font.TextStyle = .body
    var prefix = ""
    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(prefix + value.asCurrency).font(.system(style, design: .serif)).monospacedDigit().fixedSize()
            ScrollView(.horizontal, showsIndicators: false) {
                Text(prefix + value.asCurrency).font(.system(style, design: .serif)).monospacedDigit().fixedSize()
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel(prefix + value.asCurrency)
    }
}

struct DayHeader: View {
    let day: Date; let total: Double
    var body: some View {
        AdaptiveRow { Text(day.asDayTitle); AdaptiveSpacer(); Text("净收支 \(total.asCurrency)") }
            .font(.caption).foregroundStyle(.secondary)
    }
}

struct TransactionRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let transaction: TxRecord
    var body: some View {
        AdaptiveRow {
            HStack(alignment: .top, spacing: 10) {
                CategoryGlyph(name: transaction.categoryName, icon: transaction.categoryIcon)
                VStack(alignment: .leading, spacing: 5) {
                    Text(transaction.displayCategory).font(.body).fixedSize(horizontal: false, vertical: true)
                    if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }
            }
            if !typeSize.isAccessibilitySize { AdaptiveSpacer() }
            MoneyText(value: transaction.amount, prefix: transaction.type == .expense ? "−" : "+")
                .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : 185, alignment: .trailing)
        }.padding(.vertical, 6).accessibilityElement(children: .combine)
    }
    private var detail: String {
        var parts = [transaction.note].filter { !$0.isEmpty }
        if transaction.isInstallment { parts.append("分期 \(transaction.installmentIndex)/\(transaction.installmentCount)") }
        if transaction.isSubscription { parts.append("订阅平摊") }
        if transaction.date > .now { parts.append("计划") }
        return parts.joined(separator: " · ")
    }
}
