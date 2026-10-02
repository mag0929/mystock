import Foundation
import SwiftData

enum StockNameSource: Equatable {
    case cache
    case twse
    case tpex
    case yahoo
    case userSupplied
}

struct StockResolution: Equatable {
    let symbol: String
    let name: String?
    let source: StockNameSource
}

/// Resolves a Taiwan symbol to its name and keeps the result, so the name is
/// available on later screens without another lookup and works offline.
///
/// The exchange sources are preferred because they give the Chinese short name
/// that a Taiwanese investor would recognise. Yahoo is only a last resort and
/// returns an English name.
actor StockDirectory {
    private let client: HTTPClient
    private var resolved: [String: String] = [:]

    init(client: HTTPClient = URLSessionHTTPClient()) {
        self.client = client
    }

    func name(for symbol: String) async -> (name: String?, source: StockNameSource) {
        if let cached = resolved[symbol], !cached.isEmpty {
            return (cached, .cache)
        }
        if let name = try? await fetchTWSE(symbol: symbol), !name.isEmpty {
            resolved[symbol] = name
            return (name, .twse)
        }
        if let name = try? await fetchTPEx(symbol: symbol), !name.isEmpty {
            resolved[symbol] = name
            return (name, .tpex)
        }
        if let name = try? await fetchYahoo(symbol: symbol), !name.isEmpty {
            resolved[symbol] = name
            return (name, .yahoo)
        }
        return (nil, .cache)
    }

    func clearCache() {
        resolved.removeAll()
    }

    private func fetchTWSE(symbol: String) async throws -> String? {
        let calendar = Calendar(identifier: .gregorian)
        let parts = calendar.dateComponents([.year, .month], from: Date())
        guard var components = URLComponents(
            string: "https://www.twse.com.tw/exchangeReport/STOCK_DAY"
        ) else { return nil }
        if let year = parts.year, let month = parts.month {
            components.queryItems = [
                URLQueryItem(name: "response", value: "json"),
                URLQueryItem(name: "date", value: String(format: "%d%02d01", year, month)),
                URLQueryItem(name: "stockNo", value: symbol)
            ]
        }
        guard let url = components.url else { return nil }
        let data = try await client.data(from: url, headers: [:])
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            root["stat"] as? String == "OK",
            let title = root["title"] as? String
        else { return nil }
        return Self.parseTWSETitle(title, symbol: symbol)
    }

    /// The title reads "115年06月 2330 台積電           各日成交資訊".
    static func parseTWSETitle(_ title: String, symbol: String) -> String? {
        let withoutSuffix = title.replacingOccurrences(
            of: "各日成交資訊",
            with: "",
            options: .literal
        )
        let fields = withoutSuffix.split(whereSeparator: { $0 == " " || $0 == "\u{3000}" })
            .map(String.init)
        guard let index = fields.firstIndex(of: symbol) else { return nil }
        let name = fields[(index + 1)...].joined()
        return name.isEmpty ? nil : name
    }

    private func fetchTPEx(symbol: String) async throws -> String? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy/MM/dd"
        guard var components = URLComponents(
            string: "https://www.tpex.org.tw/www/zh-tw/afterTrading/otc"
        ) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "date", value: formatter.string(from: Date())),
            URLQueryItem(name: "type", value: "EW"),
            URLQueryItem(name: "response", value: "json")
        ]
        guard let url = components.url else { return nil }
        let data = try await client.data(from: url, headers: [:])
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tables = root["tables"] as? [[String: Any]],
            let fields = tables.first?["fields"] as? [String],
            let nameIndex = fields.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "名稱" }),
            let rows = tables.first?["data"] as? [[String]]
        else { return nil }
        for row in rows where row.first?.trimmingCharacters(in: .whitespaces) == symbol {
            if row.count > nameIndex {
                let name = row[nameIndex].trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { return name }
            }
        }
        return nil
    }

    private func fetchYahoo(symbol: String) async throws -> String? {
        guard var components = URLComponents(
            string: "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol).TW"
        ) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "interval", value: "1d"),
            URLQueryItem(name: "range", value: "1d")
        ]
        guard let url = components.url else { return nil }
        let data = try await client.data(
            from: url,
            headers: ["User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"]
        )
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let chart = root["chart"] as? [String: Any],
            let results = chart["result"] as? [[String: Any]],
            let meta = results.first?["meta"] as? [String: Any]
        else { return nil }
        if let short = meta["shortName"] as? String, !short.isEmpty { return short }
        if let long = meta["longName"] as? String, !long.isEmpty { return long }
        return nil
    }
}

enum StockStore {
    static func stock(for symbol: String, in context: ModelContext) throws -> Stock? {
        try context.fetch(FetchDescriptor<Stock>()).first { $0.symbol == symbol }
    }

    static func name(for symbol: String, in context: ModelContext) -> String? {
        guard let name = try? stock(for: symbol, in: context)?.name, !name.isEmpty else { return nil }
        return name
    }

    static func upsertName(_ name: String, for symbol: String, in context: ModelContext) throws {
        if let existing = try stock(for: symbol, in: context) {
            guard existing.name != name else { return }
            existing.name = name
        } else {
            context.insert(Stock(symbol: symbol, name: name))
        }
        try context.save()
    }
}