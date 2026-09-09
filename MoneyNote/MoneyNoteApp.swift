import SwiftUI
import SwiftData
import Combine
import CoreData

@MainActor
final class StoreLoader: ObservableObject {
    @Published var container: ModelContainer?
    @Published var failed = false
    init() { load() }
    func load() {
        failed = false
        let schema = Schema([TxRecord.self, LedgerModel.self, CategoryModel.self, AccountModel.self,
                             BudgetModel.self, SubscriptionModel.self])
        do {
            #if DEBUG
            let preview = ProcessInfo.processInfo.arguments.contains("--preview-data")
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: preview,
                                            cloudKitDatabase: preview ? .none : .automatic)
            #else
            let preview = false
            let config = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
            #endif
            let loaded = try ModelContainer(for: schema, configurations: [config])
            #if DEBUG
            if preview { DemoData.populate(loaded.mainContext) }
            #endif
            container = loaded
        } catch { failed = true }
    }
}

@main
struct MoneyNoteApp: App {
    @StateObject private var store = StoreLoader()
    @StateObject private var session = AppSession()
    var body: some Scene {
        WindowGroup {
            Group {
                if let container = store.container {
                    MainTabView().modelContainer(container)
                } else {
                    ContentUnavailableView {
                        Label("暂时无法打开账本", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text("原账目文件已保留。请检查设备剩余空间并重新尝试；若仍无法打开，请保留 App，联系支持协助恢复。")
                    } actions: {
                        Button("重新尝试") { store.load() }.buttonStyle(PrimaryButtonStyle())
                    }.paperScreen()
                }
            }
            .environmentObject(session)
            .onReceive(NotificationCenter.default.publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)) {
                session.cloudEvent($0)
            }
        }
    }
}
