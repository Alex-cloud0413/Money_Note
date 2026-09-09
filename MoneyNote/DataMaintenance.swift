//
//  DataMaintenance.swift
//  MoneyNote
//
//  多端 iCloud 同步后的去重合并。
//  因为每台设备首启都各建一套默认分类/账户，同步后会出现重复。
//  这里按「类型+名称」分组，给每条补一个稳定 uid，重复的留 uid 最小的那条、
//  其余合并删除。各设备都按同一规则收敛到同一份，不会来回打架。
//

import Foundation
import SwiftData

enum DataMaintenance {

    /// 入口：补 uid + 去重。空跑（无重复）时几乎零开销。
    static func deduplicate(_ context: ModelContext) throws {
        try backfillUIDs(context)
        try dedupeAccounts(context)
        try dedupeCategories(context)
        try CategoryOperations.reconcile(in: context)
        try context.save()
    }

    // 给历史数据（升级前创建的）补上 uid
    private static func backfillUIDs(_ context: ModelContext) throws {
        let cats = try context.fetch(FetchDescriptor<CategoryModel>())
        for c in cats where c.uid.isEmpty { c.uid = UUID().uuidString }
        let accs = try context.fetch(FetchDescriptor<AccountModel>())
        for a in accs where a.uid.isEmpty { a.uid = UUID().uuidString }
        try context.save()
    }

    // MARK: - 账户去重（账户被流水以关系引用，需把流水改挂到留存账户上）

    private static func dedupeAccounts(_ context: ModelContext) throws {
        let accounts = try context.fetch(FetchDescriptor<AccountModel>())
        let groups = Dictionary(grouping: accounts) { "\($0.typeRaw)|\($0.name)|\($0.initialBalance)" }
        for (_, group) in groups where group.count > 1 {
            let sorted = group.sorted { $0.uid < $1.uid }
            let survivor = sorted[0]
            for dup in sorted.dropFirst() {
                if dup.isArchived { survivor.archived = true }
                for sub in (dup.subscriptions ?? []) { sub.account = survivor }
                for rec in (dup.records ?? []) { rec.account = survivor }
                context.delete(dup)
            }
        }
    }

    // MARK: - 分类去重（流水按名称字符串引用分类，删重复大类不影响流水）

    private static func dedupeCategories(_ context: ModelContext) throws {
        // 1) 先合并重复大类，并把它们的子类改挂到留存大类下
        let all = try context.fetch(FetchDescriptor<CategoryModel>())
        let tops = all.filter { $0.parent == nil }
        let topGroups = Dictionary(grouping: tops) { "\($0.typeRaw)|\($0.name)" }
        for (_, group) in topGroups where group.count > 1 {
            let sorted = group.sorted { $0.uid < $1.uid }
            let survivor = sorted[0]
            for dup in sorted.dropFirst() {
                survivor.aliases = survivor.aliases + dup.aliases
                if dup.isArchived { survivor.archived = true }
                for child in (dup.children ?? []) { child.parent = survivor }
                context.delete(dup)
            }
        }
        try context.save()

        // 2) 再合并每个大类下重复的子类（按 父uid|子名 分组）
        let fresh = try context.fetch(FetchDescriptor<CategoryModel>())
        let subs = fresh.filter { $0.parent != nil }
        let subGroups = Dictionary(grouping: subs) { "\($0.parent?.uid ?? "")|\($0.name)" }
        for (_, group) in subGroups where group.count > 1 {
            let sorted = group.sorted { $0.uid < $1.uid }
            for dup in sorted.dropFirst() {
                sorted[0].aliases = sorted[0].aliases + dup.aliases
                if dup.isArchived { sorted[0].archived = true }
                context.delete(dup)
            }
        }
    }
}
