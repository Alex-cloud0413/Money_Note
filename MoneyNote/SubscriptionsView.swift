import SwiftUI
import SwiftData

struct SubscriptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SubscriptionModel.createdAt) private var all: [SubscriptionModel]
    @AppStorage("selectedLedger") private var ledger = LedgerChoice.legacyKey
    @State private var adding = false
    @State private var editing: SubscriptionModel?
    private var subscriptions: [SubscriptionModel] { all.filter { $0.ledgerKey == ledger } }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack { LedgerPicker(); Spacer() }.padding(.horizontal, 20)
                PaperList {
                    if subscriptions.isEmpty {
                        ContentUnavailableView {
                            Label("这个账本还没有订阅", systemImage: "arrow.triangle.2.circlepath")
                        } description: { Text("把会员、云存储等费用加进来，按月了解成本。") } actions: {
                            Button("添加订阅") { adding = true }.buttonStyle(PrimaryButtonStyle())
                        }.listRowBackground(Color.clear)
                    } else {
                        Section {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("每月常规平摊").font(.subheadline).foregroundStyle(.secondary)
                                MoneyText(value: subscriptions.filter(\.isActive).reduce(0) { $0 + $1.monthlyAmortized }, style: .largeTitle)
                                Text("\(subscriptions.filter(\.isActive).count) 个进行中 · 不含首期优惠差额").font(.caption).foregroundStyle(.secondary)
                            }.padding(20).frame(maxWidth: .infinity, alignment: .leading).paperCard()
                                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                        }
                        Section("订阅清单") {
                            ForEach(subscriptions) { sub in
                                Button { editing = sub } label: { SubscriptionRow(sub: sub) }.buttonStyle(.plain)
                                    .listRowBackground(PaperTheme.surface)
                                    .swipeActions(allowsFullSwipe: false) { Button("管理") { editing = sub }.tint(PaperTheme.accent) }
                            }
                        }
                    }
                    Section { Text("这里仅显示上方账本的订阅。停止订阅会保留历史账目；彻底删除需进入编辑页确认。")
                        .font(.footnote).foregroundStyle(.secondary) }
                }.readableWidth()
            }.paperScreen().navigationTitle("订阅").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("添加订阅")
                    }
                }.sheet(isPresented: $adding) { SubscriptionEditor() }
                .sheet(item: $editing) { SubscriptionEditor(editing: $0) }
        }
    }
}
struct SubscriptionRow: View {
    let sub: SubscriptionModel
    var body: some View {
        AdaptiveRow {
            HStack(alignment: .top, spacing: 10) {
                CategoryGlyph(name: sub.categoryName, icon: sub.categoryIcon)
                VStack(alignment: .leading, spacing: 5) {
                    Text(sub.name).font(.body)
                    Text(sub.cycle.rawValue + " · " + sub.amount.asCurrency + (sub.isActive ? "" : " · 已停止"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            AdaptiveSpacer()
            VStack(alignment: .leading, spacing: 4) {
                MoneyText(value: sub.monthlyAmortized, style: .headline)
                Text("每月平摊约").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 8).accessibilityElement(children: .combine)
    }
}
