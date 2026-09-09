import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline)
            .foregroundStyle(PaperTheme.onAccent)
            .padding(.horizontal, 20).padding(.vertical, 14)
            .frame(minHeight: 48)
            .background(PaperTheme.accent.opacity(enabled ? (configuration.isPressed ? 0.72 : 1) : 0.45),
                        in: RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// Labels stay with their values; large text stacks instead of clipping.
struct AdaptiveRow<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ViewBuilder var content: Content
    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout { content }
    }
}

struct InlineValidation: View {
    let message: String?
    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.circle")
                .font(.footnote).foregroundStyle(PaperTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
        }
    }
}

struct DraftProtection: ViewModifier {
    let dirty: Bool
    @Binding var confirming: Bool
    let discard: () -> Void
    func body(content: Content) -> some View {
        content.interactiveDismissDisabled(dirty)
            .confirmationDialog("放弃未保存的修改？", isPresented: $confirming, titleVisibility: .visible) {
                Button("放弃修改", role: .destructive, action: discard)
                Button("继续编辑", role: .cancel) {}
            } message: { Text("继续编辑可以保留当前输入。") }
    }
}

extension View {
    func protectDraft(_ dirty: Bool, confirming: Binding<Bool>, discard: @escaping () -> Void) -> some View {
        modifier(DraftProtection(dirty: dirty, confirming: confirming, discard: discard))
    }
    func readableWidth(_ width: CGFloat = 720) -> some View {
        frame(maxWidth: width).frame(maxWidth: .infinity)
    }
}

struct SymbolPicker: View {
    @Binding var icon: String
    let name: String
    private let symbols: [(String, String)] = [
        ("fork.knife", "餐饮"), ("tram", "交通"), ("bag", "购物"), ("house", "居住"),
        ("headphones", "娱乐"), ("cross.case", "医疗"), ("book", "学习"), ("phone", "通讯"),
        ("airplane", "旅行"), ("gift", "礼物"), ("pawprint", "宠物"), ("briefcase", "工作"),
        ("chart.line.uptrend.xyaxis", "理财"), ("banknote", "现金"), ("creditcard", "银行卡"),
        ("wallet.bifold", "钱包"), ("tag", "标签"), ("square.grid.2x2", "其他")
    ]
    var body: some View {
        Menu {
            ForEach(symbols, id: \.0) { symbol, title in
                Button { icon = symbol } label: { Label(title, systemImage: symbol) }
            }
        } label: {
            HStack {
                Text("图标")
                Spacer()
                CategoryGlyph(name: name, icon: icon, size: 36)
                Image(systemName: "chevron.up.chevron.down").font(.caption)
            }.frame(minHeight: 44)
        }.accessibilityLabel("选择图标")
            .accessibilityValue(symbols.first { $0.0 == icon }?.1 ?? name)
    }
}

struct PaperForm<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        Form { content.listRowBackground(PaperTheme.surface) }
    }
}

struct AdaptiveSpacer: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View { if !typeSize.isAccessibilitySize { Spacer(minLength: 0) } }
}

struct PaperList<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        List { content.listRowBackground(PaperTheme.surface) }
    }
}
