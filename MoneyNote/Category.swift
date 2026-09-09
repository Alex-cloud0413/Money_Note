//
//  Category.swift
//  MoneyNote
//
//  分类的数据结构。现在分类存进数据库，可由用户增删改，
//  并支持两层：大类（parent==nil）下面挂子类（parent 指向大类）。
//

import Foundation
import SwiftData

@Model
final class CategoryModel {
    /// 分类名，例如「餐饮」「外卖」
    var name: String = ""
    /// 图标 emoji
    var icon: String = ""
    /// 收/支类型，存字符串
    var typeRaw: String = "支出"
    /// 排序用，越小越靠前
    var sortOrder: Int = 0
    /// 跨设备稳定标识，用于多端同步后的去重合并
    var uid: String = ""
    var archived: Bool? = nil
    /// Previous names let delayed imports from an older device follow a rename.
    var previousNames: String? = nil
    var isArchived: Bool { archived == true || parent?.archived == true }
    var aliases: [String] {
        get { previousNames?.components(separatedBy: "\n").filter { !$0.isEmpty } ?? [] }
        set { previousNames = newValue.isEmpty ? nil : Array(Set(newValue)).sorted().joined(separator: "\n") }
    }
    func matches(_ value: String) -> Bool { name == value || aliases.contains(value) }

    /// 父分类；大类的 parent 为 nil，子类指向它的大类
    var parent: CategoryModel?
    /// 子分类列表。删除大类时级联删掉它的子类。
    @Relationship(deleteRule: .cascade, inverse: \CategoryModel.parent)
    var children: [CategoryModel]?

    init(name: String,
         icon: String,
         type: TransactionType,
         sortOrder: Int,
         parent: CategoryModel? = nil) {
        self.name = name
        self.icon = icon
        self.typeRaw = type.rawValue
        self.sortOrder = sortOrder
        self.parent = parent
        self.uid = UUID().uuidString
    }

    var type: TransactionType {
        get { TransactionType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }

    /// 是不是大类
    var isTopLevel: Bool { parent == nil }

    /// 排好序的子类
    var sortedChildren: [CategoryModel] {
        (children ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: - 首次启动写入默认分类

    /// 如果库里一条分类都没有，就写入一套默认分类（含示例子类）。
    static func seedDefaultsIfNeeded(_ context: ModelContext) throws {
        let count = try context.fetchCount(FetchDescriptor<CategoryModel>())
        guard count == 0 else { return }

        // (大类名, 图标, [子类...])
        let expense: [(String, String, [String])] = [
            ("餐饮", "🍜", ["外卖", "餐厅", "请客吃饭", "食材采购"]),
            ("购物", "🛍️", ["日用", "服饰", "数码"]),
            ("交通", "🚗", ["公交地铁", "打车", "加油", "停车"]),
            ("居住", "🏠", ["房租", "水电", "物业"]),
            ("娱乐", "🎮", []),
            ("医疗", "💊", []),
            ("教育", "📚", []),
            ("通讯", "📱", []),
            ("旅行", "✈️", []),
            ("人情", "🎁", []),
            ("宠物", "🐾", []),
            ("其他", "💸", []),
        ]
        let income: [(String, String, [String])] = [
            ("工资", "💰", []),
            ("奖金", "🏆", []),
            ("兼职", "💼", []),
            ("理财", "📈", []),
            ("红包", "🧧", []),
            ("退款", "↩️", []),
            ("其他", "🪙", []),
        ]

        func insert(_ groups: [(String, String, [String])], type: TransactionType) {
            for (i, (name, icon, subs)) in groups.enumerated() {
                let parent = CategoryModel(name: name, icon: icon, type: type, sortOrder: i)
                context.insert(parent)
                for (j, sub) in subs.enumerated() {
                    let child = CategoryModel(name: sub, icon: icon, type: type,
                                              sortOrder: j, parent: parent)
                    context.insert(child)
                }
            }
        }

        insert(expense, type: .expense)
        insert(income, type: .income)
        try context.save()
    }
}
