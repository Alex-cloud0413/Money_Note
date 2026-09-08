//
//  StatsView.swift
//  MoneyNote
//
//  统计页：月份切换 + 支出/收入切换 + 环形饼图 + 分类排行 + 近 6 月趋势。
//

import SwiftUI
import SwiftData
import Charts

/// 一个分类的统计结果
struct CategoryStat: Identifiable {
    var id: String { name }
    let name: String
    let icon: String
    let amount: Double
    let percent: Double      // 0 ~ 1
    let color: Color
}

struct StatsView: View {
    @Query private var transactions: [TxRecord]

    @State private var month: Date = Calendar.current.startOfDay(for: .now)
    @State private var type: TransactionType = .expense

    /// 给分类上色的调色板
    private let palette: [Color] = [
        .blue, .green, .orange, .purple, .pink, .red,
        .teal, .yellow, .indigo, .mint, .cyan, .brown,
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    monthHeader
                    Picker("类型", selection: $type) {
                        ForEach(TransactionType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if stats.isEmpty {
                        emptyCard
                    } else {
                        pieCard
                        rankCard
                    }
                    trendCard
                }
                .padding()
            }
            .navigationTitle("统计")
        }
    }

    // MARK: - 月份切换

    private var monthHeader: some View {
        HStack {
            Button { changeMonth(-1) } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 32)
            }
            Spacer()
            Text(monthTitle(month)).font(.headline)
            Spacer()
            Button { changeMonth(1) } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 32)
            }
            .disabled(isCurrentMonth)
            .opacity(isCurrentMonth ? 0.3 : 1)
        }
    }

    // MARK: - 环形饼图

    private var pieCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Chart(stats) { stat in
                    SectorMark(
                        angle: .value("金额", stat.amount),
                        innerRadius: .ratio(0.62),
                        angularInset: 1.5
                    )
                    .cornerRadius(4)
                    .foregroundStyle(stat.color)
                }
                .chartLegend(.hidden)
                .frame(height: 220)

                VStack(spacing: 2) {
                    Text(type == .expense ? "总支出" : "总收入")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(total.asCurrency)
                        .font(.system(.title2, design: .rounded)).bold()
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 分类排行

    private var rankCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.element.id) { index, stat in
                HStack(spacing: 12) {
                    Text(stat.icon)
                        .font(.title3)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(stat.color.opacity(0.18)))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(stat.name)
                            Spacer()
                            Text(stat.amount.asCurrency)
                                .font(.system(.body, design: .rounded))
                        }
                        // 占比小进度条
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(.tertiarySystemBackground)).frame(height: 5)
                                Capsule().fill(stat.color)
                                    .frame(width: geo.size.width * stat.percent, height: 5)
                            }
                        }
                        .frame(height: 5)
                    }
                    Text("\(Int((stat.percent * 100).rounded()))%")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
                .padding(.vertical, 10)

                if index < stats.count - 1 { Divider() }
            }
        }
        .padding(.horizontal)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 近 6 个月趋势

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(type == .expense ? "近 6 个月支出" : "近 6 个月收入")
                .font(.subheadline).foregroundStyle(.secondary)
            Chart(trend, id: \.label) { item in
                BarMark(
                    x: .value("月份", item.label),
                    y: .value("金额", item.amount)
                )
                .foregroundStyle(type == .expense ? Color.accentColor : Color.green)
                .cornerRadius(4)
            }
            .frame(height: 160)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 空状态

    private var emptyCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.pie").font(.largeTitle).foregroundStyle(.secondary)
            Text("本月还没有\(type.rawValue)记录").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 计算

    /// 选中月、选中类型的记录
    private var monthRecords: [TxRecord] {
        transactions.filter {
            $0.type == type &&
            Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month)
        }
    }

    private var total: Double {
        monthRecords.reduce(0) { $0 + $1.amount }
    }

    /// 按大类汇总、排序、上色
    private var stats: [CategoryStat] {
        let groups = Dictionary(grouping: monthRecords) { $0.categoryName }
        let sorted = groups
            .map { (name, recs) -> (String, String, Double) in
                (name, recs.first?.categoryIcon ?? "💸", recs.reduce(0) { $0 + $1.amount })
            }
            .sorted { $0.2 > $1.2 }
        return sorted.enumerated().map { index, item in
            CategoryStat(name: item.0, icon: item.1, amount: item.2,
                         percent: total > 0 ? item.2 / total : 0,
                         color: palette[index % palette.count])
        }
    }

    /// 近 6 个月（含选中月）每月合计
    private var trend: [(label: String, amount: Double)] {
        (0..<6).reversed().map { back -> (String, Double) in
            let m = Calendar.current.date(byAdding: .month, value: -back, to: month) ?? month
            let sum = transactions
                .filter { $0.type == type && Calendar.current.isDate($0.date, equalTo: m, toGranularity: .month) }
                .reduce(0) { $0 + $1.amount }
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = "M月"
            return (f.string(from: m), sum)
        }
    }

    // MARK: - 月份工具

    private var isCurrentMonth: Bool {
        Calendar.current.isDate(month, equalTo: .now, toGranularity: .month)
    }

    private func changeMonth(_ delta: Int) {
        if let m = Calendar.current.date(byAdding: .month, value: delta, to: month) {
            month = m
        }
    }

    private func monthTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月"
        return f.string(from: date)
    }
}
