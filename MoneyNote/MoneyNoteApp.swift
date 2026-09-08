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
            LedgerModel.self,
            CategoryModel.self,
            AccountModel.self,
            BudgetModel.self,
            SubscriptionModel.self,
        ])
        #if DEBUG
        let preview = ProcessInfo.processInfo.arguments.contains("--preview-data")
        #else
        let preview = false
        #endif
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: preview,
            cloudKitDatabase: preview ? .none : .automatic
        )
        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            #if DEBUG
            if preview { DemoData.populate(container.mainContext) }
            #endif
            return container
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
