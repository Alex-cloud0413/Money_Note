import Foundation

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
