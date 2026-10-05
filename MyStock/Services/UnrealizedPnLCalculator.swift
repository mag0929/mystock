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
    /// What selling the remaining shares right now would cost in commission and
    /// transaction tax, so the user can see the profit they would actually bank.
    let estimatedSaleFees: Decimal

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
        quote: Quote?,
        rates: FeeRates = FeeRates(
            commissionRate: FeeSettings.defaultCommissionRate,
            transactionTaxRate: FeeSettings.transactionTaxRate
        )
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
                isUsingFallbackPrice: false,
                estimatedSaleFees: .zero
            )
        }
        let previousClose = quote.previousClose
        let singleDayResult: Decimal? = previousClose.map { (currentPrice - $0) * quantity }
        // Net of the fees a real sale would incur, because a gross figure reads
        // as more profit than the user would actually receive.
        let saleFees = FeeSettings.estimatedSaleFees(
            quantity: holding.totalQuantity,
            pricePerShare: currentPrice,
            rates: rates
        ).total
        let holdingResult = currentPrice * quantity - cost - saleFees
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
            isUsingFallbackPrice: quote.isFallback,
            estimatedSaleFees: saleFees
        )
    }

    static func metrics(
        for holdings: [HoldingCalculator.Holding],
        quotes: [String: Quote],
        rates: FeeRates = FeeRates(
            commissionRate: FeeSettings.defaultCommissionRate,
            transactionTaxRate: FeeSettings.transactionTaxRate
        )
    ) -> [HoldingMetrics] {
        holdings.map { metrics(for: $0, quote: quotes[$0.symbol], rates: rates) }
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