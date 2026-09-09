//
//  SettingsView.swift
//  MoneyNote
//
//  设置页：外观（深色模式）切换、导出 CSV、关于。
//

import SwiftUI
import SwiftData

/// 外观模式
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    /// 对应 SwiftUI 的配色方案；system 返回 nil 表示跟随系统
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct SettingsView: View {
    @Query private var ledgers: [LedgerModel]
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSession
    @AppStorage("appearanceMode") private var appearanceRaw = AppearanceMode.system.rawValue
    @Query(sort: \TxRecord.date, order: .reverse) private var all: [TxRecord]
    private var transactions: [TxRecord] { all.filter { !$0.isTrashed } }
    @State private var csvURL: URL?
    @State private var exportDate: Date?
    @State private var exportError: String?
    @State private var exporting = false
    @State private var showCategories = false
    @State private var showSubscriptions = false
    @State private var showPinned = false
    @State private var showTrash = false
    var body: some View {
        NavigationStack {
            PaperForm {
                Section("管理") {
                    Button { showCategories = true } label: { Label("分类管理", systemImage: "square.grid.2x2") }
                    Button { showSubscriptions = true } label: { Label("订阅管理", systemImage: "arrow.triangle.2.circlepath") }
                    Button { showPinned = true } label: { Label("关注分类", systemImage: "pin") }
                    Button { showTrash = true } label: { Label("最近删除", systemImage: "trash") }
                }
                Section("外观") {
                    Picker("外观模式", selection: $appearanceRaw) {
                        ForEach(AppearanceMode.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                }
                Section("数据状态") {
                    Label(session.cloudStatus, systemImage: "icloud")
                    if let success = session.lastCloudSuccess {
                        LabeledContent("最近同步完成", value: success.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let saved = session.lastSaved {
                        LabeledContent("本次最近保存", value: saved.formatted(date: .omitted, time: .standard))
                    }
                    Text("账目先保存在本机。iCloud 由系统自动同步，离线时可继续记账；这里仅报告系统实际返回的同步结果。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Button(exporting ? "正在准备…" : "准备最新账单 CSV", action: export)
                        .disabled(exporting || transactions.isEmpty)
                    if let url = csvURL {
                        ShareLink(item: url) { Label("分享已准备的账单", systemImage: "square.and.arrow.up") }
                        if let exportDate { Text("生成于 \(exportDate.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                    }
                    if transactions.isEmpty { Text("暂无账目可导出").foregroundStyle(.secondary) }
                    InlineValidation(message: exportError)
                } header: { Text("导出") } footer: {
                    Text("包含所有账本的有效账目，不包含最近删除。修改账目后可重新准备最新文件。")
                }
                Section("关于") {
                    LabeledContent("名称", value: "轻账记")
                    LabeledContent("版本", value: appVersion)
                    LabeledContent("有效账目", value: "\(transactions.count) 笔")
                }
            }.readableWidth().paperScreen().navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .sheet(isPresented: $showCategories) { CategoryManagerView() }
                .sheet(isPresented: $showSubscriptions) { SubscriptionsView() }
                .sheet(isPresented: $showPinned) { PinnedCategoryPicker() }
                .sheet(isPresented: $showTrash) { RecentlyDeletedView() }
        }
    }
    private var appVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "1.2")（\(info["CFBundleVersion"] as? String ?? "5")）"
    }
    private func export() {
        exporting = true; exportError = nil; csvURL = nil
        let date = Date.now
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm"
        let choices = LedgerChoice.choices(ledgers)
        var rows = ["日期,类型,金额,大类,子类,账户,账本,备注,分期,状态"]
        for record in transactions {
            let fields = [df.string(from: record.date), record.type.rawValue, String(format: "%.2f", record.amount),
                          record.categoryName, record.subcategoryName, record.account?.name ?? "",
                          choices.first { $0.id == record.ledgerKey }?.name ?? record.ledgerKey,
                          record.note, record.isInstallment ? "\(record.installmentIndex)/\(record.installmentCount)" : "",
                          record.date > date ? "计划" : "已记入"]
            rows.append(fields.map(CSVExport.escape).joined(separator: ","))
        }
        let csv = "\u{FEFF}" + rows.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("轻账记-账单-\(UUID().uuidString.prefix(8)).csv")
        do {
            try Data(csv.utf8).write(to: url, options: .atomic)
            csvURL = url; exportDate = date
        } catch { exportError = "导出失败，请检查设备剩余空间后重试。" }
        exporting = false
    }
}
