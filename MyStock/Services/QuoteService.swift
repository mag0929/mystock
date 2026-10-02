import Foundation

enum QuoteSource: String, Sendable {
    case yahooFinance
    case twse
    case tpex
}

struct Quote: Equatable, Sendable {
    let symbol: String
    let currentPrice: Decimal?
    let previousClose: Decimal?
    let source: QuoteSource?
    let isFallback: Bool

    static func unavailable(symbol: String) -> Quote {
        Quote(symbol: symbol, currentPrice: nil, previousClose: nil, source: nil, isFallback: false)
    }

    var isAvailable: Bool { currentPrice != nil }

    var changePercentage: Decimal? {
        guard let currentPrice, let previousClose, previousClose != 0 else { return nil }
        return (currentPrice - previousClose) / previousClose
    }
}

actor QuoteService {
    private let client: HTTPClient
    private var cache: [String: Quote] = [:]

    init(client: HTTPClient = URLSessionHTTPClient()) {
        self.client = client
    }

    func cachedQuote(for symbol: String) -> Quote? {
        cache[symbol]
    }

    func clearCache() {
        cache.removeAll()
    }

    func quote(for symbol: String) async -> Quote {
        if let cached = cache[symbol] {
            return cached
        }
        let resolved = await fetch(symbol: symbol)
        cache[symbol] = resolved
        return resolved
    }

    func quotes(for symbols: [String]) async -> [String: Quote] {
        var result: [String: Quote] = [:]
        for symbol in Set(symbols) {
            result[symbol] = await quote(for: symbol)
        }
        return result
    }

    private func fetch(symbol: String) async -> Quote {
        if let yahoo = try? await fetchYahoo(symbol: symbol) {
            return Quote(symbol: symbol, currentPrice: yahoo.current, previousClose: yahoo.previous, source: .yahooFinance, isFallback: false)
        }
        if let fallback = try? await fetchExchange(symbol: symbol) {
            return Quote(
                symbol: symbol,
                currentPrice: fallback.price,
                previousClose: fallback.price,
                source: fallback.source,
                isFallback: true
            )
        }
        return .unavailable(symbol: symbol)
    }

    private struct YahooQuote {
        let current: Decimal
        let previous: Decimal
    }

    private func fetchYahoo(symbol: String) async throws -> YahooQuote {
        let url = try yahooURL(symbol: symbol)
        let data = try await client.data(
            from: url,
            headers: ["User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"]
        )
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let chart = root["chart"] as? [String: Any],
            Self.errorPayload(in: chart) == nil,
            let results = chart["result"] as? [[String: Any]],
            let result = results.first,
            let meta = result["meta"] as? [String: Any],
            let price = (meta["regularMarketPrice"] as? NSNumber)?.decimalValue,
            price > 0
        else {
            throw QuoteError.noUsablePrice(symbol: symbol)
        }
        let previous = (meta["chartPreviousClose"] as? NSNumber)?.decimalValue
            ?? (meta["previousClose"] as? NSNumber)?.decimalValue
            ?? price
        return YahooQuote(current: price, previous: previous)
    }

    private func yahooURL(symbol: String) throws -> URL {
        guard var components = URLComponents(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol).TW") else {
            throw QuoteError.malformedResponse(source: "yahoo")
        }
        components.queryItems = [
            URLQueryItem(name: "interval", value: "1d"),
            URLQueryItem(name: "range", value: "1d")
        ]
        guard let url = components.url else { throw QuoteError.malformedResponse(source: "yahoo") }
        return url
    }

    private func fetchExchange(symbol: String) async throws -> (price: Decimal, source: QuoteSource) {
        if let price = try? await fetchTWSE(symbol: symbol) {
            return (price, .twse)
        }
        let price = try await fetchTPEx(symbol: symbol)
        return (price, .tpex)
    }

    private func fetchTWSE(symbol: String) async throws -> Decimal {
        var queryItems: [URLQueryItem] = []
        let calendar = Calendar(identifier: .gregorian)
        let dateParts = calendar.dateComponents([.year, .month], from: Date())
        if let year = dateParts.year, let month = dateParts.month {
            queryItems = [
                URLQueryItem(name: "response", value: "json"),
                URLQueryItem(name: "date", value: String(format: "%d%02d01", year, month)),
                URLQueryItem(name: "stockNo", value: symbol)
            ]
        }
        guard var urlComponents = URLComponents(string: "https://www.twse.com.tw/exchangeReport/STOCK_DAY") else {
            throw QuoteError.malformedResponse(source: "twse")
        }
        urlComponents.queryItems = queryItems
        guard let url = urlComponents.url else { throw QuoteError.malformedResponse(source: "twse") }

        let data = try await client.data(from: url, headers: [:])
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            root["stat"] as? String == "OK",
            let rows = root["data"] as? [[String]]
        else {
            throw QuoteError.noUsablePrice(symbol: symbol)
        }
        guard
            let fields = root["fields"] as? [String],
            let closeIndex = fields.firstIndex(where: { field in
                field.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) == "收盤價"
            })
        else {
            throw QuoteError.malformedResponse(source: "twse")
        }
        for row in rows.reversed() where row.count > closeIndex {
            if let price = Self.parseDecimal(row[closeIndex]), price > 0 {
                return price
            }
        }
        throw QuoteError.noUsablePrice(symbol: symbol)
    }

    private func fetchTPEx(symbol: String) async throws -> Decimal {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy/MM/dd"
        let today = dateFormatter.string(from: Date())
        guard var urlComponents = URLComponents(string: "https://www.tpex.org.tw/www/zh-tw/afterTrading/otc") else {
            throw QuoteError.malformedResponse(source: "tpex")
        }
        urlComponents.queryItems = [
            URLQueryItem(name: "date", value: today),
            URLQueryItem(name: "type", value: "EW"),
            URLQueryItem(name: "response", value: "json")
        ]
        guard let url = urlComponents.url else { throw QuoteError.malformedResponse(source: "tpex") }

        let data = try await client.data(from: url, headers: [:])
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tables = root["tables"] as? [[String: Any]],
            let table = tables.first,
            let rows = table["data"] as? [[String]]
        else {
            throw QuoteError.noUsablePrice(symbol: symbol)
        }
        for row in rows where row.first?.trimmingCharacters(in: .whitespaces) == symbol {
            if row.count > 2, let price = Self.parseDecimal(row[2]), price > 0 {
                return price
            }
        }
        throw QuoteError.noUsablePrice(symbol: symbol)
    }

    private static func errorPayload(in chart: [String: Any]) -> [String: Any]? {
        guard let error = chart["error"] else { return nil }
        if error is NSNull { return nil }
        return error as? [String: Any] ?? ["error": "\(error)"]
    }

    private static func parseDecimal(_ text: String) -> Decimal? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        return Decimal(string: cleaned)
    }
}