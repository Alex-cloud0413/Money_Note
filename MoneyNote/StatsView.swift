import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @EnvironmentObject private var session: AppSession
    @AppStorage("selectedLedger") private var ledger = LedgerChoice.legacyKey
    @State private var type = TransactionType.expense
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    LedgerPicker()
                    MonthPicker(month: $session.month)
                    Picker("收支类型", selection: $type) {
                        ForEach(TransactionType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    StatsBreakdown(ledger: ledger, month: session.month, type: type)
                }.padding(20).readableWidth(1100)
            }.paperScreen().navigationTitle("统计").navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct StatsBreakdown: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query private var records: [TxRecord]
    let ledger: String; let month: Date; let type: TransactionType
    var parent: String? = nil
    private var monthly: [TxRecord] { LedgerAnalytics.records(records, ledger: ledger, month: month, type: type) }
    private var scoped: [TxRecord] { monthly.filter { parent == nil || $0.categoryName == parent } }
    private var total: Double { scoped.reduce(0) { $0 + $1.amount } }
    private var overall: Double { monthly.reduce(0) { $0 + $1.amount } }
    private var stats: [CategoryTotal] { LedgerAnalytics.categories(scoped, children: parent != nil) }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text((parent == nil ? "本月" : parent!) + type.rawValue)
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                MoneyText(value: total, style: .largeTitle)
                Text("\(scoped.count) 笔" + (parent == nil ? "" : " · 占本月\(type.rawValue) \(percent(overall > 0 ? total / overall : 0))"))
                    .font(.footnote).foregroundStyle(.secondary)
                if scoped.contains(where: { $0.date > .now }) {
                    Text("包含未来日期的计划账目").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(PaperTheme.ink).frame(height: 1.2) }
            .overlay(alignment: .bottom) { Rectangle().fill(PaperTheme.rule).frame(height: 0.7) }
            if stats.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("这个范围还没有账目。")
                        .font(.title2.weight(.semibold))
                    Text("可以切换月份或账本。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 26)
                .overlay(alignment: .top) { Rectangle().fill(PaperTheme.rule).frame(height: 0.7) }
            } else {
                ViewThatFits(in: .horizontal) {
                    if !typeSize.isAccessibilitySize {
                        HStack(alignment: .top, spacing: 20) {
                            rankings.frame(minWidth: 470)
                            trend.frame(width: 320)
                        }
                    }
                    VStack(spacing: 20) { rankings; trend }
                }
            }
        }
    }
    private var rankings: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(parent == nil ? "分类构成" : "子分类构成").font(.headline).padding(.bottom, 5)
            Text(parent == nil ? "选择分类查看子类" : "选择子类查看账目")
                .font(.caption).foregroundStyle(.secondary).padding(.bottom, 8)
            ForEach(stats) { stat in
                if let parent {
                    NavigationLink {
                        StatsTransactions(ledger: ledger, month: month, type: type, parent: parent, child: stat.name)
                    } label: { rankRow(stat) }
                    .buttonStyle(.plain)
                } else {
                    NavigationLink {
                        ScrollView {
                            StatsBreakdown(ledger: ledger, month: month, type: type, parent: stat.name)
                                .padding(20).readableWidth(1100)
                        }.paperScreen().navigationTitle(stat.name).navigationBarTitleDisplayMode(.inline)
                    } label: { rankRow(stat) }
                        .buttonStyle(.plain).accessibilityIdentifier("category-" + stat.name)
                }
                if stat.id != stats.last?.id { Divider() }
            }
        }
        .padding(.vertical, 16)
        .overlay(alignment: .top) { Rectangle().fill(PaperTheme.rule).frame(height: 0.7) }
    }
    private func rankRow(_ stat: CategoryTotal) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AdaptiveRow {
                Text(stat.name).font(.body)
                AdaptiveSpacer()
                MoneyText(value: stat.amount, style: .headline)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            HStack(spacing: 12) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(PaperTheme.rule).frame(height: 2)
                        Rectangle().fill(PaperTheme.ink)
                            .frame(width: geometry.size.width * min(max(stat.share, 0), 1), height: 2)
                    }
                }
                .frame(height: 2)
                .accessibilityHidden(true)
                Text(percent(stat.share)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            if parent != nil {
                Text("占本月\(type.rawValue) \(percent(overall > 0 ? stat.amount / overall : 0))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 14).contentShape(Rectangle()).accessibilityElement(children: .combine)
    }
    private var trend: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("近六个月" + type.rawValue).font(.headline)
            Chart(0..<6, id: \.self) { index in
                let date = Calendar.current.date(byAdding: .month, value: index - 5, to: month) ?? month
                let value = LedgerAnalytics.records(records, ledger: ledger, month: date, type: type, parent: parent).reduce(0) { $0 + $1.amount }
                BarMark(x: .value("月份", date.formatted(.dateTime.month(.twoDigits))), y: .value("金额", value))
                    .foregroundStyle(index == 5 ? PaperTheme.accent : PaperTheme.accent.opacity(0.28))
                    .accessibilityLabel(date.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "zh_CN"))))
                    .accessibilityValue((parent.map { $0 + "，" } ?? "") + type.rawValue + value.asCurrency)
            }.frame(height: 170)
            DisclosureGroup("查看每月金额") {
                ForEach(0..<6, id: \.self) { index in
                    let date = Calendar.current.date(byAdding: .month, value: index - 5, to: month) ?? month
                    let value = LedgerAnalytics.records(records, ledger: ledger, month: date, type: type, parent: parent).reduce(0) { $0 + $1.amount }
                    AdaptiveRow {
                        Text(date.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "zh_CN"))))
                        AdaptiveSpacer(); MoneyText(value: value)
                    }.padding(.vertical, 6).accessibilityElement(children: .combine)
                }
            }.font(.subheadline)
        }
        .padding(.vertical, 16)
        .overlay(alignment: .top) { Rectangle().fill(PaperTheme.rule).frame(height: 0.7) }
    }
    private func percent(_ value: Double) -> String { String(format: "%.1f%%", value * 100) }
}

struct StatsTransactions: View {
    @Query(sort: \TxRecord.date, order: .reverse) private var records: [TxRecord]
    @Query private var subscriptions: [SubscriptionModel]
    @State private var editing: TxRecord?
    @State private var editingSubscription: SubscriptionModel?
    let ledger: String; let month: Date; let type: TransactionType; let parent: String; let child: String
    private var scoped: [TxRecord] {
        LedgerAnalytics.records(records, ledger: ledger, month: month, type: type, parent: parent)
            .filter { ($0.subcategoryName.isEmpty ? "未分子类" : $0.subcategoryName) == child }
    }
    var body: some View {
        PaperList {
            Section {
                Text(month.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "zh_CN"))) + " · " + parent)
                    .font(.subheadline).foregroundStyle(.secondary)
                MoneyText(value: scoped.reduce(0) { $0 + $1.amount }, style: .title)
            }
            ForEach(scoped) { record in
                Button {
                    if let sub = subscriptions.first(where: { $0.uid == record.subscriptionUID }), record.isSubscription { editingSubscription = sub }
                    else { editing = record }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.date.asDayTitle).font(.caption).foregroundStyle(.secondary)
                        TransactionRow(transaction: record)
                    }
                }.buttonStyle(.plain).listRowBackground(PaperTheme.surface)
            }
        }.readableWidth().paperScreen().navigationTitle(child).navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editing) { TransactionEditor(editing: $0) }
            .sheet(item: $editingSubscription) { SubscriptionEditor(editing: $0) }
    }
}
