//
//  Calculator.swift
//  MoneyNote
//
//  自定义计算器键盘：带 ＋－×÷，输入时实时算结果。
//

import SwiftUI

/// 计算金额表达式的小工具
enum Calc {
    /// 把表达式字符串算成数字。支持 + - × ÷，带乘除优先级。
    /// 输入由键盘严格控制（开头是数字、运算符之间夹数字），所以这里不用考虑太乱的情况。
    static func evaluate(_ raw: String) -> Double? {
        let s = raw.replacingOccurrences(of: "×", with: "*")
                   .replacingOccurrences(of: "÷", with: "/")

        // 拆成 [数字, 运算符, 数字, ...]
        var tokens: [String] = []
        var current = ""
        for ch in s {
            if "+-*/".contains(ch) {
                tokens.append(current); current = ""
                tokens.append(String(ch))
            } else {
                current.append(ch)
            }
        }
        tokens.append(current)
        // 去掉末尾可能多出来的运算符（用户停在 "30+"）
        if tokens.last == "" {
            tokens.removeLast()
            if let last = tokens.last, "+-*/".contains(last) { tokens.removeLast() }
        }
        guard let first = tokens.first, let f0 = Double(first) else { return nil }

        // 第一遍：先算 × ÷
        var nums: [Double] = [f0]
        var ops: [String] = []
        var i = 1
        while i + 1 < tokens.count {
            let op = tokens[i]
            guard let n = Double(tokens[i + 1]) else { break }
            switch op {
            case "*": nums[nums.count - 1] *= n
            case "/":
                if n == 0 { return nil }
                nums[nums.count - 1] /= n
            default:
                ops.append(op); nums.append(n)
            }
            i += 2
        }
        // 第二遍：再算 + −
        var result = nums[0]
        for (k, op) in ops.enumerated() {
            result += (op == "-") ? -nums[k + 1] : nums[k + 1]
        }
        return result.isFinite ? result : nil
    }

    /// 把数字格式化成干净的文字：整数不带小数，否则最多两位
    static func format(_ value: Double) -> String {
        if value == value.rounded() {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
    }
}

/// 计算器键盘视图。text 是正在输入的表达式，onDone 是按「完成」时的动作。
struct CalculatorKeypad: View {
    @Binding var text: String
    /// 为 true 时，按下第一个数字键会先把原内容清空（用于编辑已有金额）
    @Binding var clearOnNextInput: Bool
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

    var body: some View {
        VStack(spacing: 8) {
            ForEach(keys, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { key in
                        keyButton(key)
                    }
                }
            }
            // 最后一行：清空 + 完成/＝
            HStack(spacing: 8) {
                Button {
                    text = ""
                } label: {
                    Text("清空").keyLabel()
                }
                .buttonStyle(.plain)
                .background(PaperTheme.soft, in: RoundedRectangle(cornerRadius: 12))

                Button {
                    if hasOperator {
                        if let v = Calc.evaluate(text) { text = Calc.format(v) }
                    } else {
                        onDone()
                    }
                } label: {
                    Text(hasOperator ? "＝" : "下一步")
                        .keyLabel()
                        .foregroundStyle(PaperTheme.onAccent)
                }
                .buttonStyle(.plain)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(10)
        .background(PaperTheme.paper)
    }

    private func keyButton(_ key: String) -> some View {
        Button {
            tap(key)
        } label: {
            Text(key).keyLabel()
        }
        .buttonStyle(.plain)
        .background(
            "+-×÷".contains(key) ? PaperTheme.soft : PaperTheme.surface,
            in: RoundedRectangle(cornerRadius: 12)
        )
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
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .contentShape(Rectangle())
    }
}
