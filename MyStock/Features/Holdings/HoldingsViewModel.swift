import Foundation
import SwiftUI

@MainActor
@Observable
final class HoldingsViewModel {
    private(set) var lots: [Lot] = []
    private(set) var holdings: [HoldingCalculator.Holding] = []
    private(set) var quotes: [String: Quote] = [:]
    private(set) var isRefreshing = false
    private(set) var loadError: String?

    private let quoteService: QuoteService

    init(quoteService: QuoteService = QuoteService()) {
        self.quoteService = quoteService
    }

    var quoteUnavailableSymbols: [String] {
        holdings
            .filter { ($0.lots.map(\.symbol).first ?? "") != "" }
            .map(\.symbol)
            .filter { quotes[$0]?.isAvailable != true }
            .sorted()
    }

    func load(lots: [Lot]) {
        self.lots = lots
        holdings = HoldingCalculator.currentHoldings(from: lots)
    }

    func onScreenAppeared() async {
        await refreshQuotes()
    }

    func onPullToRefresh() async {
        await quoteService.clearCache()
        await refreshQuotes()
    }

    private func refreshQuotes() async {
        let symbols = holdings.map(\.symbol)
        guard !symbols.isEmpty else {
            quotes = [:]
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        let fetched = await quoteService.quotes(for: symbols)
        quotes = fetched
        loadError = fetched.values.contains { $0.isAvailable } ? nil : "無法取得報價"
    }
}