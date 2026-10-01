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
    static let paper = adaptive(0xFFFFFF, 0x202020)
    static let surface = adaptive(0xFFFFFF, 0x292929)
    static let ink = adaptive(0x000000, 0xEEEEEE)
    static let accent = adaptive(0x000000, 0xFFFFFF)
    static let onAccent = adaptive(0xFCFAF4, 0x000000)
    static let rule = adaptive(0xD8D8D8, 0x4A4A4A)
    static let soft = adaptive(0xF1F1F1, 0x353535)
    static let warning = adaptive(0x555555, 0xBBBBBB)
    static let chart: [Color] = [0x000000, 0x414141, 0x777777, 0x999999, 0xB8B8B8, 0xD0D0D0].map {
        adaptive(UInt32($0), UInt32(0xFFFFFF - $0))
    }

    static func glyphSymbol(icon: String, name: String) -> String? {
        if !icon.isEmpty, UIImage(systemName: icon) != nil { return icon }
        let legacy = ["🍜": "fork.knife", "🛍️": "bag", "🚗": "tram", "🏠": "house",
                      "🎮": "headphones", "💊": "cross.case", "📚": "book", "📱": "phone",
                      "✈️": "airplane", "🎁": "gift", "🐾": "pawprint", "💸": "banknote",
                      "💰": "briefcase", "🏆": "trophy", "💼": "briefcase", "📈": "chart.line.uptrend.xyaxis",
                      "🧧": "gift", "↩️": "arrow.uturn.backward", "🪙": "banknote", "💵": "banknote",
                      "🏦": "creditcard", "💳": "creditcard", "👛": "wallet.bifold", "🏷️": "tag", "🔁": "arrow.triangle.2.circlepath"]
        if let mapped = legacy[icon] { return mapped }
        return icon.isEmpty ? symbol(name) : nil
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
                    Image("PaperTextureCrumpled")
                        .resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .saturation(colorScheme == .dark ? 1 : 0)
                        .contrast(colorScheme == .dark ? 1 : 1.12)
                        .blendMode(colorScheme == .dark ? .softLight : .multiply)
                        .opacity(colorScheme == .dark ? 0.10 : 0.46)
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
    var icon: String = ""
    var size: CGFloat = 42
    var body: some View {
        Group {
            if let symbol = PaperTheme.glyphSymbol(icon: icon, name: name) {
                Image(systemName: symbol)
            } else { Text(icon) }
        }
        .font(.system(size: size * 0.43, weight: .light))
        .foregroundStyle(PaperTheme.ink)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension View {
    func paperScreen() -> some View {
        self.scrollContentBackground(.hidden)
            .background { PaperBackground() }
            .listRowBackground(PaperTheme.surface)
            .foregroundStyle(PaperTheme.ink)
            .tint(PaperTheme.accent)
    }
}

struct MonthPicker: View {
    @Binding var month: Date
    var body: some View {
        HStack(spacing: 4) {
            Button { change(-1) } label: { Image(systemName: "chevron.left").font(.subheadline).frame(width: 44, height: 44) }
                .accessibilityLabel("上个月")
            Spacer()
            Text(month.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "zh_CN"))))
                .font(.headline).monospacedDigit()
            Spacer()
            Button { change(1) } label: { Image(systemName: "chevron.right").font(.subheadline).frame(width: 44, height: 44) }
                .accessibilityLabel("下个月")
        }
    }
    private func change(_ value: Int) {
        month = Calendar.current.date(byAdding: .month, value: value, to: month) ?? month
    }
}
