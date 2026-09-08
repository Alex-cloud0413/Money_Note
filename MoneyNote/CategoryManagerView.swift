//
//  CategoryManagerView.swift
//  MoneyNote
//
//  分类管理：大类列表，点某个大类就地下拉展开它的子类，
//  可在下拉里直接改名、加子类、删子类，再点一下收起。
//

import SwiftUI
import SwiftData

struct CategoryManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CategoryModel.sortOrder) private var all: [CategoryModel]

    @State private var type: TransactionType = .expense
    /// 记录哪些大类当前是展开的
    @State private var expandedIDs: Set<PersistentIdentifier> = []

    private var tops: [CategoryModel] {
        all.filter { $0.parent == nil && $0.type == type }
           .sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("类型", selection: $type) {
                    ForEach(TransactionType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()

                List {
                    ForEach(tops) { cat in
                        TopCategoryRow(
                            category: cat,
                            expanded: Binding(
                                get: { expandedIDs.contains(cat.persistentModelID) },
                                set: { open in
                                    if open { expandedIDs.insert(cat.persistentModelID) }
                                    else { expandedIDs.remove(cat.persistentModelID) }
                                }
                            )
                        )
                    }
                    .onDelete { offsets in
                        for i in offsets { modelContext.delete(tops[i]) }
                    }

                    Button {
                        addTopCategory()
                    } label: {
                        Label("添加大类", systemImage: "plus.circle.fill")
                    }
                }
            }
            .navigationTitle("分类管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func addTopCategory() {
        let order = (tops.last?.sortOrder ?? -1) + 1
        let new = CategoryModel(name: "新分类", icon: "🏷️", type: type, sortOrder: order)
        modelContext.insert(new)
    }
}

/// 一个大类行：上面是图标+名字+展开按钮，展开后就地显示子类
private struct TopCategoryRow: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var category: CategoryModel
    @Binding var expanded: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("图标", text: $category.icon)
                    .font(.title3)
                    .frame(width: 40)
                    .multilineTextAlignment(.center)
                TextField("分类名称", text: $category.name)
                Spacer()
                Button {
                    withAnimation { expanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        if !category.sortedChildren.isEmpty {
                            Text("\(category.sortedChildren.count)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)

            if expanded {
                VStack(spacing: 0) {
                    ForEach(category.sortedChildren) { child in
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.caption).foregroundStyle(.secondary)
                            TextField("子类名称", text: Bindable(child).name)
                            Spacer()
                            Button {
                                modelContext.delete(child)
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 6)
                        .padding(.leading, 8)
                    }

                    Button {
                        addChild()
                    } label: {
                        Label("添加子类", systemImage: "plus")
                            .font(.subheadline)
                    }
                    .padding(.vertical, 6)
                    .padding(.leading, 8)
                }
                .padding(.top, 4)
            }
        }
    }

    private func addChild() {
        let order = (category.sortedChildren.last?.sortOrder ?? -1) + 1
        let child = CategoryModel(name: "新子类", icon: category.icon,
                                  type: category.type, sortOrder: order, parent: category)
        modelContext.insert(child)
    }
}
