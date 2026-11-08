import Foundation

enum EntryCurrency: String, Codable, CaseIterable, Identifiable {
    case CNY, USD, EUR, GBP, JPY, HKD, TWD, SGD, AUD, CAD, CHF, KRW, NZD, THB, MYR

    var id: Self { self }
    var title: String {
        let name = Locale(identifier: "zh_CN").localizedString(forCurrencyCode: rawValue) ?? rawValue
        return "\(name) · \(rawValue)"
    }
    var scale: Double { self == .JPY || self == .KRW ? 1 : 100 }
    func rounded(_ amount: Double) -> Double { (amount * scale).rounded() / scale }
    func display(_ amount: Double) -> String {
        amount.formatted(.currency(code: rawValue).presentation(.isoCode))
    }
}

struct FXQuote: Codable, Equatable {
    var currency: EntryCurrency
    var rate: Double
    var timestamp: Date
    var historical: Bool

    func converted(_ original: Double) -> Double {
        EntryCurrency.CNY.rounded(currency.rounded(original) * rate)
    }
}

struct ForeignAmount: Codable, Equatable {
    var original: Double
    let quote: FXQuote

    init(original: Double, quote: FXQuote) {
        self.original = original
        self.quote = quote
    }

    init?(payload: String?) {
        guard let payload, let decoded = try? JSONDecoder().decode(Self.self, from: Data(payload.utf8)) else { return nil }
        self = decoded
    }

    var payload: String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

enum ExchangeRate {
    private struct Latest: Decodable {
        var base: String
        var target: String
        var rate: Double
        var timestamp: String
    }
    private struct Historical: Decodable {
        var base: String
        var quote: String
        var rate: Double
        var date: String
    }

    enum Failure: Error { case unavailable }

    static func fetch(_ currency: EntryCurrency, for date: Date, now: Date = .now,
                      session: URLSession = .shared) async throws -> FXQuote {
        let historical = date < Calendar.current.startOfDay(for: now)
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let day = dayFormatter.string(from: date)
        let quote: FXQuote
        if historical {
            let url = URL(string: "https://api.frankfurter.dev/v2/rate/\(currency.rawValue)/CNY?date=\(day)")!
            let response: Historical = try await request(url, session: session)
            guard response.base == currency.rawValue, response.quote == "CNY",
                  response.date <= day, let timestamp = dayFormatter.date(from: response.date),
                  date.timeIntervalSince(timestamp) < 8 * 86_400 else { throw Failure.unavailable }
            quote = FXQuote(currency: currency, rate: response.rate, timestamp: timestamp, historical: true)
        } else {
            let url = URL(string: "https://fxapi.app/api/\(currency.rawValue.lowercased())/cny.json")!
            let response: Latest = try await request(url, session: session)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let timestamp = formatter.date(from: response.timestamp)
                ?? ISO8601DateFormatter().date(from: response.timestamp)
            guard response.base == currency.rawValue, response.target == "CNY", let timestamp,
                  (-300...259_200).contains(now.timeIntervalSince(timestamp)) else { throw Failure.unavailable }
            quote = FXQuote(currency: currency, rate: response.rate, timestamp: timestamp, historical: false)
        }
        guard quote.rate.isFinite, quote.rate > 0 else { throw Failure.unavailable }
        return quote
    }

    private static func request<T: Decodable>(_ url: URL, session: URLSession) async throws -> T {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw Failure.unavailable }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
