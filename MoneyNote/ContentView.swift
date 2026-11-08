import SwiftUI
import SwiftData
import CoreData
import Combine

struct ContentView: View {
    private struct TimelineRowID: Hashable {
        let record: PersistentIdentifier
    }

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("selectedLedger") private var ledger = LedgerChoice.legacyKey
    @Query(sort: \TxRecord.date, order: .reverse) private var transactions: [TxRecord]
    @Query private var subscriptions: [SubscriptionModel]
    @Query private var budgets: [BudgetModel]
    @State private var showingAdd = false
    @State private var showingSettings = false
    @State private var todayExpanded = false
    @State private var editingRecord: TxRecord?
    @State private var editingSubscription: SubscriptionModel?
    @State private var maintenanceTask: Task<Void, Never>?
    private var records: [TxRecord] { LedgerAnalytics.records(transactions, ledger: ledger, month: session.month) }
    private var expense: Double { records.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount } }
    private var income: Double { records.filter { $0.type == .income }.reduce(0) { $0 + $1.amount } }
    private var todayExpenses: [TxRecord] {
        transactions.filter {
            !$0.isTrashed && $0.ledgerKey == ledger && $0.type == .expense &&
            Calendar.current.isDateInToday($0.date)
        }
    }
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
                    LedgerMonthHeader(month: $session.month)
                    if wide {
                        HStack(alignment: .top, spacing: 4) {
                            ledgerList { summaryRows }.frame(width: min(380, geometry.size.width * 0.34))
                            recordList(includeSummary: false)
                        }
                    } else { recordList(includeSummary: true) }
                }.readableWidth(1200)
            }.paperScreen(textureStrength: 0.45).navigationTitle("轻账记").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showingSettings = true } label: { Label("设置", systemImage: "gearshape") }
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
        VStack(alignment: .leading, spacing: 18) {
            MonthLedgerSummary(expense: expense, income: income)
            if let budget = BudgetRules.effective(budgets, ledger: ledger, month: session.month).first(where: { $0.isTotal }) {
                BudgetProgressCard(title: "总预算", icon: "circle.dashed", spent: expense, limit: budget.amount,
                                   compact: true)
            }
            PinnedCategoryCards(records: records)
        }
        .padding(.top, 8)
        .padding(.bottom, 18)
    }

    private var summaryRows: some View {
        let expenses = todayExpenses
        return Section {
            summary.listRowInsets(ledgerRowInsets)
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
            Button { todayExpanded.toggle() } label: {
                HStack(spacing: 10) {
                    AdaptiveRow {
                        Text("今日支出").font(.subheadline.weight(.semibold))
                        AdaptiveSpacer()
                        Text(expenses.reduce(0) { $0 + $1.amount }.asCurrency)
                            .font(.subheadline).monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .rotationEffect(.degrees(todayExpanded ? 90 : 0))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: todayExpanded)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("todayExpenseToggle")
            .accessibilityValue(todayExpanded ? "已展开" : "已收起")
            .listRowInsets(ledgerRowInsets)
            .listRowBackground(Color.clear).listRowSeparator(.hidden)

            if todayExpanded {
                if expenses.isEmpty {
                    Text("今天还没有支出")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                        .listRowInsets(ledgerRowInsets)
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                } else {
                    ForEach(expenses) { record in
                        transactionListRow(record, mutesAllAllocations: true)
                            .accessibilityIdentifier("todayExpenseRow")
                    }
                }
            }
        }
    }

    private var ledgerRowInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)
    }

    private func ledgerList<Rows: View>(@ViewBuilder rows: () -> Rows) -> some View {
        PaperList(content: rows)
            .listStyle(.plain).listSectionSpacing(10).scrollContentBackground(.hidden)
            .contentMargins(.top, 8, for: .scrollContent)
    }

    private func recordList(includeSummary: Bool) -> some View {
        ScrollViewReader { reader in
            ledgerList {
                if includeSummary { summaryRows }
                if records.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("这个月还是空白。")
                                .font(.title2.weight(.semibold))
                            Text("第一笔会记入上方所选月份。")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Button("记一笔") { showingAdd = true }
                                .buttonStyle(PrimaryButtonStyle())
                                .padding(.top, 10)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 28)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
                ForEach(byDay.keys.sorted(by: >), id: \.self) { day in
                    Section {
                        ForEach(byDay[day] ?? []) { record in
                            transactionListRow(record)
                                .id(TimelineRowID(record: record.persistentModelID))
                        }
                    } header: {
                        DayHeader(day: day, total: (byDay[day] ?? []).reduce(0) { $0 + $1.signedAmount })
                            .listRowInsets(ledgerRowInsets)
                    }
                }
            }
            .onChange(of: session.selectedRecord) { _, record in
                if let record { reader.scrollTo(TimelineRowID(record: record), anchor: .center) }
            }
        }
    }

    private func transactionListRow(_ record: TxRecord, mutesAllAllocations: Bool = false) -> some View {
        Button { edit(record) } label: {
            TransactionRow(transaction: record, subscription: subscription(for: record),
                           mutesAllAllocations: mutesAllAllocations)
        }
            .buttonStyle(.plain).listRowBackground(Color.clear)
            .listRowSeparator(.hidden).listRowInsets(ledgerRowInsets)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if record.isSubscription {
                    Button("管理订阅") { edit(record) }.tint(PaperTheme.accent)
                } else {
                    Button("删除", role: .destructive) { session.delete([record], in: context) }
                }
            }
    }

    private func subscription(for record: TxRecord) -> SubscriptionModel? {
        guard record.isSubscription else { return nil }
        return subscriptions.first { $0.uid == record.subscriptionUID }
    }

    private func edit(_ record: TxRecord) {
        if let sub = subscription(for: record) {
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

private struct MonthLedgerSummary: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var expenseSize = 42.0
    let expense: Double
    let income: Double
    var body: some View {
        ViewThatFits(in: .horizontal) {
            if !typeSize.isAccessibilitySize {
                HStack(alignment: .lastTextBaseline, spacing: 20) {
                    metric("当月支出", expense, font: expenseFont, alignment: .leading, showsTitle: false)
                    Spacer(minLength: 0)
                    metric("收入", income, font: .title3.weight(.medium), alignment: .trailing)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                metric("当月支出", expense, font: expenseFont, alignment: .leading, showsTitle: false, scrolls: true)
                metric("收入", income, font: .title3.weight(.medium), alignment: .leading, scrolls: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private var expenseFont: Font { .system(size: expenseSize, weight: .medium) }

    private func metric(_ title: String, _ value: Double, font: Font,
                        alignment: HorizontalAlignment, showsTitle: Bool = true, scrolls: Bool = false) -> some View {
        VStack(alignment: alignment, spacing: 5) {
            if showsTitle { Text(title).font(.subheadline).foregroundStyle(.secondary) }
            if scrolls {
                ViewThatFits(in: .horizontal) {
                    amount(value, font: font)
                    ScrollView(.horizontal) { amount(value, font: font) }
                }
            } else {
                amount(value, font: font)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value.asCurrency)
    }

    private func amount(_ value: Double, font: Font) -> some View {
        Text(value.asCurrency).font(font).monospacedDigit().fixedSize()
    }
}

struct MoneyText: View {
    let value: Double
    var style: Font.TextStyle = .body
    var prefix = ""
    var design: Font.Design = .serif
    var body: some View {
        ViewThatFits(in: .horizontal) {
            amount
            ScrollView(.horizontal, showsIndicators: false) {
                amount
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel(prefix + value.asCurrency)
    }
    private var amount: some View {
        Text(prefix + value.asCurrency).font(.system(style, design: design)).monospacedDigit().fixedSize()
    }
}

struct DayHeader: View {
    let day: Date; let total: Double
    var body: some View {
        AdaptiveRow { Text(day.asDayTitle); AdaptiveSpacer(); Text(total.asCurrency) }
            .font(.footnote.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary)
    }
}

struct TransactionRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorSchemeContrast) private var contrast
    let transaction: TxRecord
    var subscription: SubscriptionModel? = nil
    var mutesAllAllocations = false

    private static let allocationInk = PaperTheme.adaptive(0xB4B4B4, 0x585858)
    private static let allocationDetailInk = PaperTheme.adaptive(0xB8B8B8, 0x4F4F4F)
    private static let detailInk = PaperTheme.adaptive(0x6D6D6D, 0xA7A7A7)

    var body: some View {
        let ink = rowInk
        let metadataInk = isAllocation ? Self.allocationDetailInk : Self.detailInk
        AdaptiveRow {
            HStack(spacing: 12) {
                CategoryGlyph(name: transaction.categoryName, icon: transaction.categoryIcon, size: 36)
                    .background(PaperTheme.soft, in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                        .minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.78)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(ink)
                    let metadata = detail
                    if !metadata.isEmpty {
                        Text(metadata)
                            .font(.caption2)
                            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                            .minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.85)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(contrast == .increased ? PaperTheme.ink : metadataInk)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            MoneyText(value: transaction.amount, prefix: transaction.type == .expense ? "−" : "+", design: .default)
                .foregroundStyle(ink)
                .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: false)
                .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil, alignment: .trailing)
                .layoutPriority(1)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
    private var rowInk: Color {
        let muted = (mutesAllAllocations && isAllocation) || isLaterAllocation
        return contrast == .increased || !muted ? PaperTheme.ink : Self.allocationInk
    }
    private var isAllocation: Bool { transaction.isInstallment || transaction.isSubscription }
    private var isLaterAllocation: Bool {
        if let subscription {
            return SubscriptionEngine.isLaterAllocation(on: transaction.date, unit: transaction.allocation,
                                                        for: subscription)
        }
        return transaction.isInstallment && transaction.installmentIndex > 1
    }
    private var title: String {
        let note = transaction.note.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return note.isEmpty ? transaction.displayCategory : note
    }
    private var detail: String {
        var parts: [String] = []
        if transaction.isInstallment {
            let label = transaction.allocation == .day ? "按天平摊" : "分期"
            parts.append("\(label) \(transaction.installmentIndex)/\(transaction.installmentCount)")
        }
        if transaction.isSubscription {
            parts.append(transaction.allocation == .day ? "订阅 · 按天平摊" : "订阅平摊")
        }
        if let foreign = transaction.foreignAmount {
            parts.append(foreign.quote.currency.display(foreign.original))
        }
        if transaction.date > .now { parts.append("计划") }
        return parts.joined(separator: " · ")
    }
}
