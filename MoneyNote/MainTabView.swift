//
//  MainTabView.swift
//  MoneyNote
//
//  底部标签页容器：明细 + 统计。
//

import SwiftUI

struct MainTabView: View {
    // 默认仍停在「明细」(tag 0)；从左到右顺序为 预算 / 账户 / 统计 / 明细
    @State private var selection = 0
    @AppStorage("appearanceMode") private var appearanceRaw = AppearanceMode.system.rawValue

    var body: some View {
        TabView(selection: $selection) {
            BudgetView()
                .tabItem { Label("预算", systemImage: "target") }
                .tag(3)
            AccountsView()
                .tabItem { Label("账户", systemImage: "creditcard.fill") }
                .tag(2)
            StatsView()
                .tabItem { Label("统计", systemImage: "chart.pie.fill") }
                .tag(1)
            ContentView()
                .tabItem { Label("明细", systemImage: "list.bullet") }
                .tag(0)
        }
        .preferredColorScheme(AppearanceMode(rawValue: appearanceRaw)?.colorScheme)
    }
}
