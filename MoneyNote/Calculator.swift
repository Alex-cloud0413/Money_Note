import SwiftUI

/// 计算器键盘视图。text 是正在输入的表达式，onDone 是按「完成」时的动作。
struct CalculatorKeypad: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Binding var text: String
    /// 为 true 时，按下第一个数字键会先把原内容清空（用于编辑已有金额）
    @Binding var clearOnNextInput: Bool
    var canContinue = true
    var onDone: () -> Void

    /// 表达式里有没有运算符（有就显示「＝」，按一下算结果）
    private var hasOperator: Bool {
        text.contains(where: { "+-×÷".contains($0) })
    }

    // 键盘按键布局
    private let keys: [[String]] = [
        ["7", "8", "9", "÷"],
        ["4", "5", "6", "×"],
        ["1", "2", "3", "-"],
        [".", "0", "⌫", "+"],
    ]

    @State private var calculationError: String?
    var body: some View {
        VStack(spacing: 10) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(keys.enumerated()), id: \.offset) { rowIndex, row in
                        HStack(spacing: 0) {
                            ForEach(Array(row.enumerated()), id: \.offset) { keyIndex, key in
                                keyButton(key)
                                if keyIndex < row.count - 1 {
                                    Rectangle().fill(PaperTheme.rule.opacity(0.65)).frame(width: 0.5)
                                }
                            }
                        }
                        if rowIndex < keys.count - 1 {
                            Rectangle().fill(PaperTheme.rule.opacity(0.65)).frame(height: 0.5)
                        }
                    }
                }
                .overlay { Rectangle().stroke(PaperTheme.rule, lineWidth: 0.7) }
            }.scrollBounceBehavior(.basedOnSize)
            InlineValidation(message: calculationError)
            HStack(spacing: 8) {
                Button { text = ""; clearOnNextInput = false } label: { Text("清空").keyLabel() }
                    .buttonStyle(PaperKeyStyle(soft: true))
                Button {
                    if hasOperator {
                        if let value = Calc.evaluate(text), text.last.map({ !"+-×÷".contains($0) }) == true {
                            text = Calc.format(value); calculationError = nil
                        } else { calculationError = "无法计算，请检查算式与除数。" }
                    } else { onDone() }
                } label: {
                    Text(hasOperator ? "计算" : (typeSize.isAccessibilitySize ? "继续" : "下一步")).lineLimit(nil).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!hasOperator && !canContinue)
                .accessibilityIdentifier("entryNext")
            }
        }.padding(.horizontal, 20).padding(.vertical, 12).background(PaperTheme.paper)
            .onChange(of: text) { _, _ in calculationError = nil }
    }

    private func keyButton(_ key: String) -> some View {
        Button {
            tap(key)
        } label: {
            Text(key).keyLabel()
        }
        .buttonStyle(PaperKeyStyle(soft: "+-×÷".contains(key)))
        .accessibilityLabel(key == "⌫" ? "删除最后一位" : key == "÷" ? "除以" : key == "×" ? "乘以" : key)

    }

    /// 处理一次按键
    private func tap(_ key: String) {
        // 编辑金额时：按下第一个数字/小数点，先清空原金额
        let isDigit = key.count == 1 && (key.first?.isNumber ?? false)
        if clearOnNextInput && (isDigit || key == ".") {
            text = ""
            clearOnNextInput = false
        }
        switch key {
        case "⌫":
            if !text.isEmpty { text.removeLast() }
        case "+", "-", "×", "÷":
            guard let last = text.last else { return }       // 开头不让输运算符
            if "+-×÷".contains(last) {
                text.removeLast(); text.append(key)           // 连续运算符 → 替换
            } else if last == "." {
                text.removeLast(); text.append(key)           // 小数点后接运算符 → 去掉点
            } else {
                text.append(key)
            }
        case ".":
            // 当前这一段数字里已经有小数点就不再加
            let segment = text.split(whereSeparator: { "+-×÷".contains($0) }).last.map(String.init) ?? ""
            if !segment.contains(".") {
                text.append(text.isEmpty || text.last.map { "+-×÷".contains($0) } == true ? "0." : ".")
            }
        default: // 数字
            text.append(key)
        }
    }
}

/// 让按键文字统一成大号、铺满格子的样式
private extension View {
    func keyLabel() -> some View {
        self.font(.title2)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .frame(minHeight: 52)
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle())
    }
}

private struct PaperKeyStyle: ButtonStyle {
    var soft = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(PaperTheme.ink)
            .background(configuration.isPressed ? PaperTheme.rule.opacity(0.55) : (soft ? PaperTheme.soft.opacity(0.55) : Color.clear))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
