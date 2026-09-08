//
//  SubscriptionsView.swift
//  MoneyNote
//
//  订阅管理页（首页工具栏「订阅」按钮进入）。
//  顶部显示每月订阅平摊合计，下面是订阅清单；可新增/编辑/删除。
//  订阅会被 SubscriptionEngine 按月平摊并自动生成流水，计入月度统计与预算。
//

import SwiftUI
import SwiftData

struct SubscriptionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SubscriptionModel.createdAt) private var allSubscriptions: [SubscriptionModel]
    @AppStorage("selectedLedger") private var ledgerKey = LedgerChoice.legacyKey
    private var subscriptions: [SubscriptionModel] { allSubscriptions.filter { $0.ledgerKey == ledgerKey } }

    @State private var showingAdd = false
    @State private var editing: SubscriptionModel?

    /// 每月订阅平摊合计（按常规价，只统计仍在订阅中的）
    private var monthlyTotal: Double {
        subscriptions.filter { $0.isActive }.reduce(0) { $0 + $1.monthlyAmortized }
    }

    var body: some View {
        NavigationStack {
            Group {
                if subscriptions.isEmpty {
                    emptyView
                } else {
                    List {
                        Section {
                            summaryCard
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                        }
                        Section("我的订阅") {
                            ForEach(subscriptions) { sub in
                                Button {
                                    editing = sub
                                } label: {
                                    SubscriptionRow(sub: sub)
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete(perform: delete)
                        }
                        Section {
                            Text("年付 / 季付会自动按月平摊，每月生成一笔流水，计入月度汇总、统计和预算。首期优惠价只在首个周期内平摊。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .paperScreen()
            .navigationTitle("订阅")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showingAdd) { SubscriptionEditor() }
            .sheet(item: $editing) { sub in SubscriptionEditor(editing: sub) }
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 8) {
            Text("每月订阅平摊合计")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
            Text(monthlyTotal.asCurrency)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("共 \(subscriptions.filter { $0.isActive }.count) 个进行中的订阅")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.vertical, 8)
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("还没有订阅", systemImage: "arrow.triangle.2.circlepath")
        } description: {
            Text("把会员、云存储等自动续费加进来，自动按月平摊记账")
        } actions: {
            Button("添加订阅") { showingAdd = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets {
            let sub = subscriptions[index]
            SubscriptionEngine.deleteRecords(for: sub, in: modelContext)
            modelContext.delete(sub)
        }
    }
}

// MARK: - 单条订阅

struct SubscriptionRow: View {
    let sub: SubscriptionModel

    var body: some View {
        HStack(spacing: 12) {
            CategoryGlyph(name: sub.categoryName)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(sub.name).font(.body)
                    if !sub.isActive {
                        Text("已取消")
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.gray.opacity(0.2)))
                            .foregroundStyle(.secondary)
                    }
                }
                Text("\(sub.cycle.rawValue) \(sub.amount.asCurrency)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("每月≈\(sub.monthlyAmortized.asCurrency)")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.medium)
                Text(sub.categoryName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
