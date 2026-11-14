import SwiftUI
import UIKit

struct MainTabView: View {
    @EnvironmentObject private var session: AppSession
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
