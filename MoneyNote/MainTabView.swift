import SwiftUI
import UIKit

struct MainTabView: View {
    @EnvironmentObject private var session: AppSession
    @AppStorage("appearanceMode") private var appearanceRaw = AppearanceMode.system.rawValue
    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $session.selection) {
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
            StableTabBar(selection: $session.selection)
        }
        .background(PaperTheme.paper)
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

/// A fixed material surface avoids the system glass lens morphing between tabs.
private struct StableTabBar: View {
    @Binding var selection: Int
    private let items = [
        (title: "明细", symbol: "text.alignleft"),
        (title: "账本", symbol: "books.vertical"),
        (title: "统计", symbol: "chart.bar.xaxis"),
        (title: "预算", symbol: "circle.dashed")
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                let selected = selection == index
                Button {
                    guard selection != index else { return }
                    EntryFeedback.tap()
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { selection = index }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 20, weight: .medium))
                            .frame(height: 24)
                        Text(item.title).font(.caption.weight(.medium))
                    }
                    .foregroundStyle(PaperTheme.ink.opacity(selected ? 1 : 0.58))
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .padding(.vertical, 3)
                    .background(selected ? PaperTheme.ink.opacity(0.08) : Color.clear, in: Capsule())
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityIdentifier("mainTab-\(index)")
                .accessibilityValue(selected ? "已选中" : "未选中")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(6)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().stroke(PaperTheme.rule.opacity(0.7), lineWidth: 0.5) }
        .frame(maxWidth: 600)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mainTabBar")
        .transaction { $0.disablesAnimations = true }
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
