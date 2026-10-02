import Foundation

struct HoldingMetrics: Equatable {
    let symbol: String
    let displayName: String?
    let currentPrice: Decimal?
    let priceChangePercentage: Decimal?
    let singleDayResult: Decimal?
    let holdingResult: Decimal?
    let holdingReturnPercentage: Decimal?
    let totalQuantity: Int
    let totalRemainingCost: Decimal
    let isUsingFallbackPrice: Bool

    var isAvailable: Bool { currentPrice != nil }

    /// Nil when nothing is held, so the screen can say why instead of
    /// printing a zero that reads like a real cost.
    var averageCostPerShare: Decimal? {
        guard totalQuantity > 0 else { return nil }
        return totalRemainingCost / Decimal(totalQuantity)
    }
}

struct PortfolioTotals: Equatable {
    let holdingResult: Decimal
    let singleDayResult: Decimal
    let excludedSymbolCount: Int
    let includedSymbolCount: Int

    static let empty = PortfolioTotals(
        holdingResult: .zero,
        singleDayResult: .zero,
        excludedSymbolCount: 0,
        includedSymbolCount: 0
    )
}

enum UnrealizedPnLCalculator {
    static func metrics(
        for holding: HoldingCalculator.Holding,
        quote: Quote?
    ) -> HoldingMetrics {
        let quantity = Decimal(holding.totalQuantity)
        let cost = holding.totalRemainingCost
        guard let quote, let currentPrice = quote.currentPrice else {
            return HoldingMetrics(
                symbol: holding.symbol,
                displayName: holding.displayName,
                currentPrice: nil,
                priceChangePercentage: nil,
                singleDayResult: nil,
                holdingResult: nil,
                holdingReturnPercentage: nil,
                totalQuantity: holding.totalQuantity,
                totalRemainingCost: cost,
                isUsingFallbackPrice: false
            )
        }
        let previousClose = quote.previousClose
        let singleDayResult: Decimal? = previousClose.map { (currentPrice - $0) * quantity }
        let holdingResult = currentPrice * quantity - cost
        return HoldingMetrics(
            symbol: holding.symbol,
            displayName: holding.displayName,
            currentPrice: currentPrice,
            priceChangePercentage: quote.changePercentage,
            singleDayResult: singleDayResult,
            holdingResult: holdingResult,
            holdingReturnPercentage: cost == 0 ? nil : holdingResult / cost,
            totalQuantity: holding.totalQuantity,
            totalRemainingCost: cost,
            isUsingFallbackPrice: quote.isFallback
        )
    }

    static func metrics(
        for holdings: [HoldingCalculator.Holding],
        quotes: [String: Quote]
    ) -> [HoldingMetrics] {
        holdings.map { metrics(for: $0, quote: quotes[$0.symbol]) }
    }

    static func totals(from metrics: [HoldingMetrics]) -> PortfolioTotals {
        let priced = metrics.filter(\.isAvailable)
        let excluded = metrics.count - priced.count
        return PortfolioTotals(
            holdingResult: priced.compactMap(\.holdingResult).reduce(.zero, +),
            singleDayResult: priced.compactMap(\.singleDayResult).reduce(.zero, +),
            excludedSymbolCount: excluded,
            includedSymbolCount: priced.count
        )
    }
}