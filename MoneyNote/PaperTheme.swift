import SwiftUI
import UIKit

enum PaperTheme {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
    static let paper = adaptive(0xF3F0E8, 0x202020)
    static let surface = adaptive(0xFCFAF4, 0x2B2B2B)
    static let ink = adaptive(0x000000, 0xEEEEEE)
    static let accent = adaptive(0x000000, 0xFFFFFF)
    static let onAccent = adaptive(0xFCFAF4, 0x000000)
    static let rule = adaptive(0xDDDBD7, 0x484848)
    static let soft = adaptive(0xEAE8E3, 0x363636)
    static let warning = adaptive(0x555555, 0xBBBBBB)
    static let chart: [Color] = [0x000000, 0x414141, 0x777777, 0x999999, 0xB8B8B8, 0xD0D0D0].map {
        adaptive(UInt32($0), UInt32(0xFFFFFF - $0))
    }

    static func symbol(_ name: String) -> String {
        switch name {
        case "餐饮", "饮食", "吃饭": return "fork.knife"
        case "交通": return "tram"
        case "购物": return "bag"
        case "居家", "住房", "生活", "居住": return "house"
        case "通讯": return "phone"
        case "娱乐": return "headphones"
        case "医疗", "健康": return "cross.case"
        case "教育", "学习": return "book"
        case "旅行", "旅游": return "airplane"
        case "人情", "红包", "礼物": return "gift"
        case "宠物": return "pawprint"
        case "工资", "奖金", "兼职", "事业": return "briefcase"
        case "理财": return "chart.line.uptrend.xyaxis"
        case "退款": return "arrow.uturn.backward"
        case "现金": return "banknote"
        case "银行卡", "信用卡": return "creditcard"
        default: return "square.grid.2x2"
        }
    }
}

/// A quiet paper texture; omitted for increased contrast and never animated.
struct PaperBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        PaperTheme.paper.overlay {
            if contrast != .increased {
                GeometryReader { geo in
                    Image("PaperTexture")
                        .resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .blendMode(colorScheme == .dark ? .softLight : .multiply)
                        .opacity(colorScheme == .dark ? 0.14 : 0.32)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct CategoryGlyph: View {
    let name: String
    var size: CGFloat = 42
    var body: some View {
        Image(systemName: PaperTheme.symbol(name))
            .font(.system(size: size * 0.43, weight: .regular))
            .foregroundStyle(PaperTheme.ink)
            .frame(width: size, height: size)
            .background(PaperTheme.soft, in: RoundedRectangle(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
    }
}

extension View {
    func paperScreen() -> some View {
        self.scrollContentBackground(.hidden)
            .background { PaperBackground() }
            .toolbarBackground(.hidden, for: .navigationBar)
            .foregroundStyle(PaperTheme.ink)
            .tint(PaperTheme.accent)
    }
    func paperCard(radius: CGFloat = 20) -> some View {
        self.background(PaperTheme.surface.opacity(0.88), in: RoundedRectangle(cornerRadius: radius))
            .overlay { RoundedRectangle(cornerRadius: radius).stroke(PaperTheme.rule.opacity(0.7), lineWidth: 0.6) }
    }
}

struct MonthPicker: View {
    @Binding var month: Date
    var body: some View {
        HStack {
            Button { change(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .accessibilityLabel("上个月")
            Spacer()
            Text(month.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "zh_CN"))))
                .font(.subheadline.weight(.medium)).monospacedDigit()
            Spacer()
            Button { change(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .accessibilityLabel("下个月")
        }
    }
    private func change(_ value: Int) {
        month = Calendar.current.date(byAdding: .month, value: value, to: month) ?? month
    }
}
