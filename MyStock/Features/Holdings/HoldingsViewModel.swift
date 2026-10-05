import Foundation
import SwiftUI
import SwiftData

struct PortfolioSummary {
    let priceChangeText: String?
    let priceChangeColor: Color
    let singleDayText: String?
    let singleDayColor: Color
    let holdingText: String?
    let holdingColor: Color
    let excludedSymbolCount: Int

    var holdingResultIsAvailable: Bool { holdingText != nil }
}

@MainActor
@Observable
final class HoldingsViewModel {
    private(set) var lots: [Lot] = []
    private(set) var holdings: [HoldingCalculator.Holding] = []
    private(set) var quotes: [String: Quote] = [:]
    private(set) var isRefreshing = false
    private(set) var loadError: String?

    private let quoteService: QuoteService

    /// Read from the settings store so an estimate of what selling would cost
    /// uses the user's own rates rather than the defaults.
    private var feeRates = FeeRates(
        commissionRate: FeeSettings.defaultCommissionRate,
        transactionTaxRate: FeeSettings.transactionTaxRate
    )

    init(quoteService: QuoteService = QuoteService()) {
        self.quoteService = quoteService
    }

    var quoteUnavailableSymbols: [String] {
        holdings
            .map(\.symbol)
            .filter { quotes[$0]?.isAvailable != true }
            .sorted()
    }

    /// Builds a lot row carrying the stored name and the figures that make the
    /// purchase comparable to the position's current value.
    func lotRow(for lot: Lot, context: ModelContext) -> LotRowViewModel {
        let rates = (try? FeeSettingsStore.currentRates(in: context))
            ?? FeeRates(
                commissionRate: FeeSettings.defaultCommissionRate,
                transactionTaxRate: FeeSettings.transactionTaxRate
            )
        return LotRowViewModel(
            lot: lot,
            displayName: StockStore.name(for: lot.symbol, in: context),
            metrics: LotPnLCalculator.metrics(for: lot, quote: quotes[lot.symbol], rates: rates)
        )
    }

    var metrics: [String: HoldingMetrics] {
        Dictionary(
            uniqueKeysWithValues: UnrealizedPnLCalculator
                .metrics(for: holdings, quotes: quotes, rates: feeRates)
                .map { ($0.symbol, $0) }
        )
    }

    func metrics(for holding: HoldingCalculator.Holding) -> HoldingMetrics {
        UnrealizedPnLCalculator.metrics(
            for: holding,
            quote: quotes[holding.symbol],
            rates: feeRates
        )
    }

    var portfolioSummary: PortfolioSummary? {
        guard !holdings.isEmpty else { return nil }
        let allMetrics = UnrealizedPnLCalculator.metrics(
            for: holdings,
            quotes: quotes,
            rates: feeRates
        )
        let totals = UnrealizedPnLCalculator.totals(from: allMetrics)
        let pricedMetrics = allMetrics.filter(\.isAvailable)
        let weightedChange = weightedChangePercentage(from: pricedMetrics)

        return PortfolioSummary(
            priceChangeText: weightedChange.map { Format.percent($0) },
            priceChangeColor: color(for: weightedChange),
            singleDayText: Format.signedDecimal(totals.singleDayResult),
            singleDayColor: color(for: totals.singleDayResult),
            holdingText: Format.signedDecimal(totals.holdingResult),
            holdingColor: color(for: totals.holdingResult),
            excludedSymbolCount: totals.excludedSymbolCount
        )
    }

    func load(lots: [Lot]) {
        self.lots = lots
        holdings = HoldingCalculator.currentHoldings(from: lots)
    }

    /// Attaches the stored company names so the screen can show "2330 台積電"
    /// instead of a bare code.
    func applyDisplayNames(in context: ModelContext) {
        if let rates = try? FeeSettingsStore.currentRates(in: context) {
            feeRates = rates
        }
        for index in holdings.indices {
            let symbol = holdings[index].symbol
            holdings[index].displayName = StockStore.name(for: symbol, in: context)
        }
    }

    /// Loads the lots and fetches their quotes as one step, so the screen
    /// never shows holdings with no price because the fetch ran first.
    func loadAndRefresh(lots: [Lot]) async {
        load(lots: lots)
        await refreshQuotes()
    }

    func loadAndRefresh(lots: [Lot], context: ModelContext) async {
        load(lots: lots)
        applyDisplayNames(in: context)
        await refreshQuotes()
    }

    func onScreenAppeared() async {
        await refreshQuotes()
    }

    func onPullToRefresh() async {
        await quoteService.clearCache()
        await refreshQuotes()
    }

    func dismissLoadError() {
        loadError = nil
    }

    private func weightedChangePercentage(from metrics: [HoldingMetrics]) -> Decimal? {
        var marketValue = Decimal.zero
        var previousValue = Decimal.zero
        for metric in metrics {
            guard let current = metric.currentPrice else { continue }
            let quantity = Decimal(metric.totalQuantity)
            marketValue += current * quantity
            if let change = metric.priceChangePercentage {
                previousValue += (current / (change + 1)) * quantity
            }
        }
        guard previousValue != 0 else { return nil }
        return (marketValue - previousValue) / previousValue
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
        loadError = fetched.values.contains(where: \.isAvailable) ? nil : "無法取得報價"
    }

    private func color(for value: Decimal?) -> Color {
        guard let value else { return .secondary }
        if value > 0 { return .red }
        if value < 0 { return .green }
        return .primary
    }
}