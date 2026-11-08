import SwiftUI
import Combine

struct CurrencyPicker: View {
    @Binding var currency: EntryCurrency

    var body: some View {
        Picker("币种", selection: $currency) {
            ForEach(EntryCurrency.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("entryCurrency")
    }
}

@MainActor
final class FXLookup: ObservableObject {
    private struct Request: Equatable {
        var currency: EntryCurrency
        var day: Date
    }

    private var request: Request?
    @Published private(set) var quote: FXQuote?
    @Published private(set) var failed = false
    @Published private(set) var revision = 0

    func id(currency: EntryCurrency, date: Date) -> String {
        "\(currency.rawValue)-\(Calendar.current.startOfDay(for: date).timeIntervalSince1970)-\(revision)"
    }

    func matching(_ currency: EntryCurrency, date: Date) -> FXQuote? {
        request == Request(currency: currency, day: Calendar.current.startOfDay(for: date)) ? quote : nil
    }

    func use(_ quote: FXQuote?, currency: EntryCurrency, date: Date) {
        request = Request(currency: currency, day: Calendar.current.startOfDay(for: date))
        self.quote = quote
        failed = false
    }

    func retry() { failed = false; revision += 1 }

    func load(currency: EntryCurrency, date: Date) async {
        guard currency != .CNY, matching(currency, date: date) == nil else { return }
        use(nil, currency: currency, date: date)
        do {
            let result = try await ExchangeRate.fetch(currency, for: date)
            try Task.checkCancellation()
            use(result, currency: currency, date: date)
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }
}

struct FXQuoteRow: View {
    let quote: FXQuote?
    let amount: Double?
    var fixedAmount: Double? = nil
    let failed: Bool
    let retry: () -> Void

    var body: some View {
        if let quote {
            VStack(alignment: .leading, spacing: 5) {
                if let amount, amount.isFinite, amount >= 0 {
                    Text("折合 \((fixedAmount ?? quote.converted(amount)).asCurrency)").font(.subheadline.weight(.medium))
                }
                let rate = quote.rate.formatted(.number.precision(.fractionLength(0...8)))
                let time = quote.timestamp.formatted(.dateTime
                    .year().month(.twoDigits).day(.twoDigits)
                    .locale(Locale(identifier: "zh_CN")))
                let updated = quote.historical ? time : time + " " + quote.timestamp.formatted(.dateTime.hour().minute().locale(Locale(identifier: "zh_CN")))
                Text("1 \(quote.currency.rawValue) = \(rate) CNY · \(updated)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("fxQuote")
        } else if failed {
            VStack(alignment: .leading, spacing: 8) {
                Text("暂未取得汇率，金额输入已保留。").font(.footnote).foregroundStyle(.secondary)
                Button("重新获取汇率", action: retry).buttonStyle(.borderless)
            }
        } else {
            ProgressView("正在获取汇率").font(.footnote)
        }
    }
}
