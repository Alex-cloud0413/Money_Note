import SwiftUI
import SwiftData
import CoreData
import Combine
import UIKit

struct MainTabView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var maintenanceTask: Task<Void, Never>?
    @State private var maintenanceNeedsRetry = false
    @State private var returnedFromBackground = false
    @AppStorage("appearanceMode") private var appearanceRaw = AppearanceMode.system.rawValue

    var body: some View {
        NavigationTabs(selection: session.tabs)
            .environment(\.locale, Locale(identifier: "zh_CN"))
            .tint(PaperTheme.accent)
            .background {
                WindowAppearance(colorScheme: AppearanceMode(rawValue: appearanceRaw)?.colorScheme)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            // Root lifetime keeps ordinary tab appearances off the maintenance
            // path while still observing imports when another page is visible.
            .task { maintain() }
            .onChange(of: session.month) { _, month in sync(upTo: month) }
            .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)
                .receive(on: RunLoop.main)) { _ in
                maintenanceTask?.cancel()
                maintenanceTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(600))
                    guard !Task.isCancelled else { return }
                    maintain()
                }
            }
            .onReceive(session.tabs.$value.dropFirst()) { tab in
                if tab == 0 && maintenanceNeedsRetry { maintain() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { returnedFromBackground = true }
                else if phase == .active && returnedFromBackground {
                    returnedFromBackground = false
                    maintain()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)
                .receive(on: RunLoop.main)) { _ in maintain() }
    }

    private func maintain() {
        do {
            try CategoryModel.seedDefaultsIfNeeded(context)
            try DataMaintenance.deduplicate(context)
            try SubscriptionEngine.sync(context, upTo: session.month)
            maintenanceNeedsRetry = false
        }
        catch {
            context.rollback()
            maintenanceNeedsRetry = true
            session.failed("账目整理尚未完成，请稍后重新打开 App。")
        }
    }

    private func sync(upTo date: Date) {
        do { try SubscriptionEngine.sync(context, upTo: date) }
        catch {
            context.rollback()
            maintenanceNeedsRetry = true
            session.failed("订阅平摊尚未更新，请稍后重试。")
        }
    }
}

private struct NavigationTabs: View {
    @ObservedObject var selection: AppTabSelection

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selection.value) {
                ContentView()
                    .tabItem { Label("明细", systemImage: "text.alignleft") }.tag(0)
                    .toolbar(.hidden, for: .tabBar)
                LedgersView()
                    .tabItem { Label("账本", systemImage: "books.vertical") }.tag(1)
                    .toolbar(.hidden, for: .tabBar)
                StatsView()
                    .tabItem { Label("统计", systemImage: "chart.bar.xaxis") }.tag(2)
                    .toolbar(.hidden, for: .tabBar)
                BudgetView()
                    .tabItem { Label("预算", systemImage: "circle.dashed") }.tag(3)
                    .toolbar(.hidden, for: .tabBar)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            SessionNotice()
            ControlledGlassTabBar(selection: $selection.value, onSelectionFeedback: EntryFeedback.tap)
        }
        .background(PaperTheme.paper)
    }
}

/// Window traits update open sheets immediately and let system appearance resume cleanly.
private struct WindowAppearance: UIViewRepresentable {
    let colorScheme: ColorScheme?

    func makeUIView(context: Context) -> AppearanceView { AppearanceView() }

    func updateUIView(_ uiView: AppearanceView, context: Context) {
        uiView.appearance = colorScheme.map { $0 == .dark ? .dark : .light } ?? .unspecified
    }

    final class AppearanceView: UIView {
        var appearance: UIUserInterfaceStyle = .unspecified {
            didSet { applyAppearance() }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            applyAppearance()
        }

        private func applyAppearance() {
            guard let window, window.overrideUserInterfaceStyle != appearance else { return }
            window.overrideUserInterfaceStyle = appearance
        }
    }
}
