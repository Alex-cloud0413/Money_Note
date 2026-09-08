import SwiftUI

struct MainTabView: View {
    @State private var selection = 0
    @AppStorage("appearanceMode") private var appearanceRaw = AppearanceMode.system.rawValue
    var body: some View {
        TabView(selection: $selection) {
            ContentView().tabItem { Label("明细", systemImage: "text.alignleft") }.tag(0)
            LedgersView().tabItem { Label("账本", systemImage: "books.vertical") }.tag(1)
            StatsView().tabItem { Label("统计", systemImage: "chart.bar.xaxis") }.tag(2)
            BudgetView().tabItem { Label("预算", systemImage: "circle.dashed") }.tag(3)
        }
        .tint(PaperTheme.accent)
        .preferredColorScheme(AppearanceMode(rawValue: appearanceRaw)?.colorScheme)
    }
}
