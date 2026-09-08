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
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearanceMode") private var appearanceRaw = AppearanceMode.system.rawValue
    @Query(sort: \TxRecord.date, order: .reverse) private var transactions: [TxRecord]

    @State private var csvURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section("外观") {
                    Picker("外观模式", selection: $appearanceRaw) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    if let url = csvURL {
                        ShareLink(item: url) {
                            Label("导出账单 CSV", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Label("暂无可导出的账单", systemImage: "square.and.arrow.up")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("数据")
                } footer: {
                    Text("导出全部账单为 CSV 表格，可用 Excel / numbers 打开。")
                }

                Section("关于") {
                    infoRow("名称", "MoneyNote")
                    infoRow("版本", appVersion)
                    infoRow("账单数", "\(transactions.count) 笔")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear(perform: regenerateCSV)
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    // MARK: - CSV 导出

    private func regenerateCSV() {
        guard !transactions.isEmpty else { csvURL = nil; return }
        let csv = makeCSV()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MoneyNote-账单.csv")
        try? csv.data(using: .utf8)?.write(to: url)
        csvURL = url
    }

    private func makeCSV() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"

        var rows = ["日期,类型,金额,大类,子类,账户,备注,分期"]
        for t in transactions {
            let fields = [
                df.string(from: t.date),
                t.type.rawValue,
                String(format: "%.2f", t.amount),
                t.categoryName,
                t.subcategoryName,
                t.account?.name ?? "",
                t.note,
                t.isInstallment ? "\(t.installmentIndex)/\(t.installmentCount)" : ""
            ]
            rows.append(fields.map(escape).joined(separator: ","))
        }
        // 开头加 BOM，Excel 打开中文不乱码
        return "\u{FEFF}" + rows.joined(separator: "\n")
    }

    private func escape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }
}
