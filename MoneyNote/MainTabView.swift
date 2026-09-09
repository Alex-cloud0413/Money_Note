import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var session: AppSession
    @AppStorage("appearanceMode") private var appearanceRaw = AppearanceMode.system.rawValue
    var body: some View {
        TabView(selection: $session.selection) {
            ContentView().tabItem { Label("明细", systemImage: "text.alignleft") }.tag(0)
            LedgersView().tabItem { Label("账本", systemImage: "books.vertical") }.tag(1)
            StatsView().tabItem { Label("统计", systemImage: "chart.bar.xaxis") }.tag(2)
            BudgetView().tabItem { Label("预算", systemImage: "circle.dashed") }.tag(3)
        }
        .overlay(alignment: .bottom) { SessionNotice().padding(.bottom, 68) }
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .tint(PaperTheme.accent)
        .preferredColorScheme(AppearanceMode(rawValue: appearanceRaw)?.colorScheme)
    }
}
