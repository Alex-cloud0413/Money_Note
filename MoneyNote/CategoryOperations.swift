import Foundation
import SwiftData

/// Category names in legacy records are updated together with the category.
/// No record is reassigned to an arbitrary fallback category.
enum CategoryOperations {
    enum EditError: LocalizedError {
        case invalidName, duplicate
        var errorDescription: String? {
            switch self {
            case .invalidName: return "分类名称请填写 1–24 个字，不能包含换行。"
            case .duplicate: return "这个名称已被同级分类或其旧名称使用，请换一个名称。"
            }
        }
    }

    static func validate(_ name: String, category: CategoryModel?, parent: CategoryModel?,
                         type: TransactionType, in context: ModelContext) throws {
        guard !name.isEmpty, name.count <= 24, !name.contains("\n") else { throw EditError.invalidName }
        let all = try context.fetch(FetchDescriptor<CategoryModel>())
        if all.contains(where: { $0 !== category && $0.type == type &&
            $0.parent?.persistentModelID == parent?.persistentModelID && $0.matches(name) }) {
            throw EditError.duplicate
        }
    }

    static func update(_ category: CategoryModel, name: String, icon: String, in context: ModelContext) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try validate(clean, category: category, parent: category.parent, type: category.type, in: context)
        if category.name != clean {
            category.aliases = category.aliases + [category.name]
            category.name = clean
        }
        category.icon = icon
        try reconcile(in: context, refreshingIconFor: category.uid)
        try context.save()
    }

    static func reconcile(in context: ModelContext, refreshingIconFor categoryUID: String? = nil) throws {
        let all = try context.fetch(FetchDescriptor<CategoryModel>())
        let tops = all.filter { $0.parent == nil }
        let records = try context.fetch(FetchDescriptor<TxRecord>())
        let subscriptions = try context.fetch(FetchDescriptor<SubscriptionModel>())
        let budgets = try context.fetch(FetchDescriptor<BudgetModel>())
        for parent in tops {
            for record in records where record.type == parent.type && parent.matches(record.categoryName) {
                if record.categoryName != parent.name { record.categoryName = parent.name }
                if categoryUID == parent.uid && record.categoryIcon != parent.icon { record.categoryIcon = parent.icon }
                if let child = parent.sortedChildren.first(where: { $0.matches(record.subcategoryName) }) {
                    if record.subcategoryName != child.name { record.subcategoryName = child.name }
                }
            }
            if parent.type == .expense {
                for sub in subscriptions where parent.matches(sub.categoryName) {
                    if sub.categoryName != parent.name { sub.categoryName = parent.name }; if categoryUID == parent.uid && sub.categoryIcon != parent.icon { sub.categoryIcon = parent.icon }
                    if let child = parent.sortedChildren.first(where: { $0.matches(sub.subcategoryName) }) {
                        if sub.subcategoryName != child.name { sub.subcategoryName = child.name }
                    }
                }
                for budget in budgets where !budget.isTotal && parent.matches(budget.categoryName) {
                    if budget.categoryName != parent.name { budget.categoryName = parent.name }
                }

            }
        }
    }
    static func resolvedPins(_ raw: String, categories: [CategoryModel]) -> [String] {
        raw.components(separatedBy: "\n").filter { !$0.isEmpty }.reduce(into: []) { result, oldName in
            let name = categories.first { $0.parent == nil && $0.type == .expense && $0.matches(oldName) }?.name ?? oldName
            if !result.contains(name) { result.append(name) }
        }
    }

}
