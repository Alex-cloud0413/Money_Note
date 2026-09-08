import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Query private var transactions: [TxRecord]
    @AppStorage("selectedLedger") private var ledger = LedgerChoice.legacyKey
    @State private var month = Date.now
    @State private var type: TransactionType = .expense
    @State private var parent: String?

    private var monthly: [TxRecord] {
        LedgerAnalytics.records(transactions, ledger: ledger, month: month, type: type)
    }
    private var scoped: [TxRecord] { monthly.filter { parent == nil || $0.categoryName == parent } }
    private var total: Double { scoped.reduce(0) { $0 + $1.amount } }
    private var stats: [CategoryTotal] { LedgerAnalytics.categories(scoped, children: parent != nil) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    LedgerPicker()
                    MonthPicker(month: $month)
                    Picker("收支类型", selection: $type) {
                        ForEach(TransactionType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    if let parent {
                        HStack {
                            CategoryGlyph(name: parent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(parent + " · 子分类").font(.title3.weight(.medium))
                                Text("下方占比以本类合计为分母").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if stats.isEmpty {
                        ContentUnavailableView("本月还没有\(type.rawValue)记录", systemImage: "chart.bar.xaxis",
                                               description: Text("记下第一笔，慢慢看清钱的去向。"))
                    } else {
                        distribution
                        VStack(spacing: 0) {
                            HStack {
                                Text(parent == nil ? "分类构成" : "子分类构成").font(.headline)
                                Spacer()
                                Text(parent == nil ? "点分类查看细分" : "占本类 / 占本月")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.padding(.bottom, 12)
                            ForEach(Array(stats.enumerated()), id: \.element.id) { i, stat in
                                if parent == nil {
                                    Button { parent = stat.name } label: { rankRow(stat, index: i) }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("category-" + stat.name)
                                } else { rankRow(stat, index: i) }
                                if i < stats.count - 1 { Divider().overlay(PaperTheme.rule) }
                            }
                        }.padding(20).paperCard()
                    }
                    trendCard
                }.padding(20)
            }.id(parent).paperScreen().navigationTitle("统计")
                .toolbar {
                    if parent != nil {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { parent = nil } label: { Label("全部分类", systemImage: "chevron.left") }
                        }
                    }
                }
                .onChange(of: ledger) { _, _ in parent = nil }
                .onChange(of: type) { _, _ in parent = nil }
        }
    }

    private var distribution: some View {
        VStack(spacing: 12) {
            ZStack {
                Chart(Array(stats.enumerated()), id: \.element.id) { i, stat in
                    SectorMark(angle: .value("金额", stat.amount), innerRadius: .ratio(0.78), angularInset: 2)
                        .cornerRadius(3).foregroundStyle(PaperTheme.chart[i % PaperTheme.chart.count])
                        .accessibilityLabel(stat.name)
                        .accessibilityValue("\(stat.amount.asCurrency)，占比\(percent(stat.share))")
                }.chartLegend(.hidden).frame(height: 224)
                VStack(spacing: 8) {
                    Text(parent == nil ? "本月" + type.rawValue : "本类" + type.rawValue)
                        .font(.caption).foregroundStyle(.secondary)
                    Text(total.asCurrency).font(.system(.title2, design: .serif)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6).frame(maxWidth: 165)
                    Text("\(scoped.count) 笔").font(.caption2).foregroundStyle(.secondary)
                }.allowsHitTesting(false)
            }
            if parent != nil {
                let whole = monthly.reduce(0) { $0 + $1.amount }
                Text("占本月\(type.rawValue) \(percent(whole > 0 ? total / whole : 0))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.padding(24).frame(maxWidth: .infinity).paperCard()
    }

    private func rankRow(_ stat: CategoryTotal, index: Int) -> some View {
        VStack(spacing: 9) {
            HStack(spacing: 10) {
                Circle().fill(PaperTheme.chart[index % PaperTheme.chart.count]).frame(width: 8, height: 8)
                Text(stat.name).font(.subheadline)
                Spacer(minLength: 6)
                Text(stat.amount.asCurrency).font(.subheadline.weight(.medium)).monospacedDigit()
                if parent == nil { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary) }
            }
            HStack(spacing: 14) {
                GeometryReader { geo in
                    Capsule().fill(PaperTheme.soft).overlay(alignment: .leading) {
                        Capsule().fill(PaperTheme.chart[index % PaperTheme.chart.count])
                            .frame(width: geo.size.width * min(1, max(0, stat.share)))
                    }
                }.frame(height: 4)
                let all = monthly.reduce(0) { $0 + $1.amount }
                Text(parent == nil ? percent(stat.share) : "\(percent(stat.share)) / \(percent(all > 0 ? stat.amount / all : 0))")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
        }.padding(.vertical, 13).contentShape(Rectangle())
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text((parent.map { $0 + " · " } ?? "") + "近六个月" + type.rawValue).font(.headline)
            Chart(0..<6, id: \.self) { i in
                let date = Calendar.current.date(byAdding: .month, value: i - 5, to: month) ?? month
                let value = LedgerAnalytics.records(transactions, ledger: ledger, month: date, type: type, parent: parent)
                    .reduce(0) { $0 + $1.amount }
                BarMark(x: .value("月份", date, unit: .month), y: .value("金额", value))
                    .foregroundStyle(i == 5 ? PaperTheme.accent : PaperTheme.accent.opacity(0.35))
                    .cornerRadius(4)
            }.frame(height: 155)
                .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.defaultDigits)) } }
        }.padding(20).paperCard()
    }

    private func percent(_ share: Double) -> String { String(format: "%.1f%%", share * 100) }
}
