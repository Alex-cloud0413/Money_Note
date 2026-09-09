import SwiftUI
import SwiftData

struct RecentlyDeletedView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var session: AppSession
    @Query(sort: \TxRecord.date, order: .reverse) private var records: [TxRecord]
    @State private var error: String?
    private var trash: [TxRecord] { records.filter(\.isTrashed) }
    var body: some View {
        NavigationStack {
            PaperList {
                Section { Text("这里的账目不计入余额、统计或预算。恢复后会回到原日期、分类、账户和账本；App 不会自动清空这些记录。")
                    .font(.footnote).foregroundStyle(.secondary) }
                if trash.isEmpty { ContentUnavailableView("没有已删除账目", systemImage: "trash") }
                ForEach(trash) { record in
                    VStack(alignment: .leading, spacing: 10) {
                        TransactionRow(transaction: record)
                        Button("恢复这笔账") {
                            record.deletedAt = nil
                            do { try context.save(); session.saved("账目已恢复") }
                            catch { context.rollback(); self.error = "恢复失败，请稍后重试。" }
                        }.frame(minHeight: 44)
                    }.listRowBackground(PaperTheme.surface)
                }
            }.readableWidth().paperScreen().navigationTitle("最近删除").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .alert("未能恢复", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("好") { error = nil }
                } message: { Text(error ?? "") }
        }
    }
}
