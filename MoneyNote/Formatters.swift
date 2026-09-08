//
//  Formatters.swift
//  MoneyNote
//
//  金额、日期的格式化小工具，给整个 App 复用。
//

import Foundation

extension Double {
    /// 把数字格式化成「¥1,234.50」这样的金额文字
    var asCurrency: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencySymbol = "¥"
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f.string(from: NSNumber(value: self)) ?? "¥0.00"
    }
}

extension Date {
    /// 分组标题用：今天 / 昨天 / 6月5日 周四
    var asDayTitle: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) { return "今天" }
        if cal.isDateInYesterday(self) { return "昨天" }

        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        // 同一年只显示「月日 周几」，跨年才显示年份
        if cal.isDate(self, equalTo: .now, toGranularity: .year) {
            f.dateFormat = "M月d日 EEEE"
        } else {
            f.dateFormat = "yyyy年M月d日 EEEE"
        }
        return f.string(from: self)
    }
}
