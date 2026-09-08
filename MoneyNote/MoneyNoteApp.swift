//
//  MoneyNoteApp.swift
//  MoneyNote
//
//  Created by 高一鸣 on 2026/6/7.
//

import SwiftUI
import SwiftData

@main
struct MoneyNoteApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            TxRecord.self,
            CategoryModel.self,
            AccountModel.self,
            BudgetModel.self,
            SubscriptionModel.self,
        ])
        // cloudKitDatabase: .automatic —— 当工程开启了 iCloud(CloudKit) 能力时自动同步；
        // 没开启能力时退回本地存储，不影响使用。
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
        .modelContainer(sharedModelContainer)
    }
}
