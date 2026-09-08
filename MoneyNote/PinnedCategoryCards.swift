//
//  PinnedCategoryCards.swift
//  MoneyNote
//
//  首页顶部「关注的大类」横向卡片：实时显示本月在某个大类下的支出。
//  用户可自定义关注哪些大类，选择存在 @AppStorage（本机）。
//

import SwiftUI
import SwiftData

struct PinnedCategoryCards: View {
    /// 当前所选月份的全部流水（由首页传入，实时计算）
    let records: [TxRecord]

    @AppStorage("pinnedCategoryNames") private var pinnedRaw = ""
    @Query(sort: \CategoryModel.sortOrder) private var allCategories: [CategoryModel]
    @State private var showPicker = false

    private let cardHeight: CGFloat = 52

    /// 关注的大类名（用换行分隔，避免分类名里有逗号）
    private var pinnedNames: [String] {
        pinnedRaw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    private func icon(for name: String) -> String {
        allCategories.first { $0.parent == nil && $0.type == .expense && $0.name == name }?.icon ?? "📌"
    }

    /// 本月该大类的支出合计
    private func amount(for name: String) -> Double {
        records.filter { $0.type == .expense && $0.categoryName == name }
            .reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        Group {
            if pinnedNames.isEmpty {
                Button {
                    showPicker = true
                } label: {
                    Label("关注分类", systemImage: "plus.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
                                .foregroundStyle(.secondary.opacity(0.4))
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.bottom, 4)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(pinnedNames, id: \.self) { name in
                            card(name: name)
                        }
                        manageButton
                    }
                    .padding(.horizontal)
                }
                .frame(height: cardHeight)
                .padding(.bottom, 4)
            }
        }
        .sheet(isPresented: $showPicker) { PinnedCategoryPicker() }
    }

    private func card(name: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: PaperTheme.symbol(name)).font(.subheadline)
                Text(name)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            Text(amount(for: name).asCurrency)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12)
        .frame(width: 116, height: cardHeight, alignment: .leading)
        .background(PaperTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private var manageButton: some View {
        Button {
            showPicker = true
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "slider.horizontal.3").font(.subheadline)
                Text("管理").font(.caption2)
            }
            .foregroundStyle(.secondary)
            .frame(width: 56, height: cardHeight)
            .background(PaperTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 选择关注哪些大类

struct PinnedCategoryPicker: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("pinnedCategoryNames") private var pinnedRaw = ""
    @Query(sort: \CategoryModel.sortOrder) private var allCategories: [CategoryModel]

    private var expenseTopCategories: [CategoryModel] {
        allCategories.filter { $0.parent == nil && $0.type == .expense }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var pinnedNames: [String] {
        pinnedRaw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    private func toggle(_ name: String) {
        var names = pinnedNames
        if let idx = names.firstIndex(of: name) {
            names.remove(at: idx)
        } else {
            names.append(name)
        }
        pinnedRaw = names.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("选中的大类会显示在首页顶部，实时显示本月在该大类下的支出。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("支出大类") {
                    ForEach(expenseTopCategories) { cat in
                        Button {
                            toggle(cat.name)
                        } label: {
                            HStack {
                                Label(cat.name, systemImage: PaperTheme.symbol(cat.name))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if pinnedNames.contains(cat.name) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
            }
            .paperScreen()
            .navigationTitle("关注的大类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
