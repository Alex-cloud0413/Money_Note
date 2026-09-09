import Foundation
import SwiftData

/// Run only on a COPY of an existing store, never against the original backup.
@main
struct StoreUpgradeRehearsal {
    @MainActor static func main() throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let schema = Schema([TxRecord.self, CategoryModel.self, AccountModel.self, BudgetModel.self, SubscriptionModel.self, LedgerModel.self])
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        try CategoryModel.seedDefaultsIfNeeded(context)
        try AccountModel.seedDefaultsIfNeeded(context)
        try DataMaintenance.deduplicate(context)
        try CategoryOperations.reconcile(in: context)
        try context.save()
        try SubscriptionEngine.sync(context)
        let records = try context.fetch(FetchDescriptor<TxRecord>())
        precondition(records.allSatisfy { $0.amount.isFinite })
        print("PASS: store opened and app startup maintenance completed without cloud access")
    }
}
