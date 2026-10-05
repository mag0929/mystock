import Foundation
import Testing
@testable import MyStock

@Suite("Unrealized profit figures")
struct UnrealizedPnLTests {
    private func holding(
        symbol: String = "2330",
        lots: [(quantity: Int, price: Decimal, fees: Decimal, type: LotType)] = [
            (1000, 150, 0, .buy),
            (1000, 90, 0, .buy),
            (200, 0, 0, .stockAllocation)
        ],
        soldSharesPerLot: [Int: Int] = [:]
    ) -> HoldingCalculator.Holding {
        var built: [Lot] = []
        var dates = Fixtures.makeDate(2026, 1, 10)
        for entry in lots {
            let lot = Lot(
                symbol: symbol,
                lotDate: dates,
                quantity: entry.quantity,
                pricePerShare: entry.price,
                totalFees: entry.fees,
                lotType: entry.type
            )
            if let sold = soldSharesPerLot[built.count] {
                lot.remainingQuantity = entry.quantity - sold
            }
            built.append(lot)
            dates = Fixtures.makeDate(2026, built.count + 1, 20)
        }
        return HoldingCalculator.holdings(from: built).first { $0.symbol == symbol }!
    }

    private func quote(
        current: Decimal?,
        previous: Decimal?,
        fallback: Bool = false
    ) -> Quote? {
        guard current != nil || previous != nil else { return nil }
        return Quote(
            symbol: "2330",
            currentPrice: current,
            previousClose: previous,
            source: fallback ? .twse : .yahooFinance,
            isFallback: fallback
        )
    }

    @Test("Computing current price change")
    func computingCurrentPriceChange() {
        let result = UnrealizedPnLCalculator.metrics(for: holding(), quote: quote(current: 130, previous: 125))
        #expect((result.priceChangePercentage ?? .zero).rounded(scale: 4) == Decimal(string: "0.04"))
        #expect(result.currentPrice == 130)
    }

    @Test("Previous close is zero")
    func previousCloseIsZero() {
        let result = UnrealizedPnLCalculator.metrics(for: holding(), quote: quote(current: 130, previous: 0))
        #expect(result.priceChangePercentage == nil)
        #expect(result.currentPrice == 130)
    }

    @Test("Computing single day result")
    func computingSingleDayResult() {
        let gain = UnrealizedPnLCalculator.metrics(for: holding(), quote: quote(current: 130, previous: 125))
        let loss = UnrealizedPnLCalculator.metrics(for: holding(), quote: quote(current: 120, previous: 125))

        #expect(gain.singleDayResult == 11000)
        #expect(loss.singleDayResult == -11000)
        #expect(gain.totalQuantity == 2200)
    }

    @Test("Single day result unavailable without a price")
    func singleDayUnavailableWithoutPrice() {
        let result = UnrealizedPnLCalculator.metrics(for: holding(), quote: nil)
        #expect(result.singleDayResult == nil)
        #expect(result.holdingResult == nil)
        #expect(result.currentPrice == nil)
    }

    @Test("Holding profit is net of the fees a sale would incur")
    func holdingProfit() {
        let result = UnrealizedPnLCalculator.metrics(for: holding(), quote: quote(current: 130, previous: 125))
        // 286000 market value - 240000 cost - 1265 estimated sale fees.
        #expect(result.estimatedSaleFees == 1265)
        #expect(result.holdingResult == 44735)
        #expect((result.holdingReturnPercentage ?? .zero).rounded(scale: 4) == Decimal(string: "0.1864"))
    }

    @Test("Selling at the average cost still loses the fees")
    func holdingLoss() {
        let atRoundedAverage = UnrealizedPnLCalculator.metrics(for: holding(), quote: quote(current: Decimal(string: "109.09")!, previous: 109))
        let atExactAverage = UnrealizedPnLCalculator.metrics(for: holding(), quote: quote(current: Decimal(240000) / Decimal(2200), previous: 109))

        // Even at a break-even price the result is negative, because the fees
        // would be paid. Printing 0 would promise a profit the user would not get.
        #expect((atRoundedAverage.holdingResult ?? .zero).rounded(scale: 0) == -1062)
        #expect((atRoundedAverage.holdingReturnPercentage ?? .zero).rounded(scale: 4) == Decimal(string: "-0.0044"))
        #expect((atExactAverage.holdingResult ?? .zero).rounded(scale: 0) == -1060)
        #expect((atExactAverage.holdingReturnPercentage ?? .zero).rounded(scale: 4) == Decimal(string: "-0.0044"))
    }

    @Test("Zero remaining cost")
    func zeroRemainingCost() {
        let zeroCost = holding(lots: [(200, 0, 0, .stockAllocation)])
        let result = UnrealizedPnLCalculator.metrics(for: zeroCost, quote: quote(current: 50, previous: 49))

        #expect(result.totalRemainingCost == 0)
        #expect(result.holdingResult == 9956)
        #expect(result.holdingReturnPercentage == nil)
    }

    @Test("Fees included in holding cost")
    func feesIncludedInHoldingCost() {
        let withFees = holding(lots: [(1000, 150, 1425, .buy)])
        let result = UnrealizedPnLCalculator.metrics(for: withFees, quote: quote(current: 130, previous: 125))

        #expect(withFees.totalRemainingCost == 151425)
        #expect(result.holdingResult == -22000)
    }

    @Test("Fallback price is flagged on the row")
    func fallbackPriceIsFlagged() {
        let result = UnrealizedPnLCalculator.metrics(for: holding(), quote: quote(current: 128, previous: 128, fallback: true))
        #expect(result.isUsingFallbackPrice == true)
    }

    @Test("Summing across symbols")
    func summingAcrossSymbols() {
        let holdings = [
            holding(symbol: "2330", lots: [(1000, 150, 0, .buy), (1000, 90, 0, .buy), (200, 0, 0, .stockAllocation)]),
            holding(symbol: "2317", lots: [(1000, 50, 0, .buy)])
        ]
        let metrics = UnrealizedPnLCalculator.metrics(for: holdings, quotes: [
            "2330": Quote(symbol: "2330", currentPrice: 130, previousClose: 125, source: .yahooFinance, isFallback: false),
            "2317": Quote(symbol: "2317", currentPrice: 45, previousClose: 50, source: .yahooFinance, isFallback: false)
        ])

        let totals = UnrealizedPnLCalculator.totals(from: metrics)

        #expect(totals.holdingResult == 39536)
        #expect(totals.excludedSymbolCount == 0)
        #expect(totals.includedSymbolCount == 2)
    }

    @Test("Excluding symbols without prices")
    func excludingSymbolsWithoutPrices() {
        let holdings = [
            holding(symbol: "2330", lots: [(1000, 150, 0, .buy), (1000, 90, 0, .buy), (200, 0, 0, .stockAllocation)]),
            holding(symbol: "2317", lots: [(1000, 50, 0, .buy)])
        ]
        let metrics = UnrealizedPnLCalculator.metrics(for: holdings, quotes: [
            "2330": Quote(symbol: "2330", currentPrice: 130, previousClose: 125, source: .yahooFinance, isFallback: false)
        ])

        let totals = UnrealizedPnLCalculator.totals(from: metrics)

        #expect(totals.holdingResult == 44735)
        #expect(totals.excludedSymbolCount == 1)
        #expect(totals.includedSymbolCount == 1)
        #expect(metrics.first { $0.symbol == "2317" }?.isAvailable == false)
    }

    @Test("One symbol priced and one not")
    func oneSymbolPricedOneNot() {
        let holdings = [
            holding(symbol: "2330", lots: [(1000, 150, 0, .buy), (1000, 90, 0, .buy), (200, 0, 0, .stockAllocation)]),
            holding(symbol: "2317", lots: [(1000, 50, 0, .buy)])
        ]
        let metrics = UnrealizedPnLCalculator.metrics(for: holdings, quotes: [
            "2330": Quote(symbol: "2330", currentPrice: 130, previousClose: 125, source: .yahooFinance, isFallback: false)
        ])
        let totals = UnrealizedPnLCalculator.totals(from: metrics)

        let priced = metrics.first { $0.symbol == "2330" }!
        let unpriced = metrics.first { $0.symbol == "2317" }!

        #expect(priced.holdingResult == 44735)
        #expect(unpriced.holdingResult == nil)
        #expect(unpriced.priceChangePercentage == nil)
        #expect(unpriced.singleDayResult == nil)
        #expect(totals.holdingResult == 44735)
        #expect(totals.excludedSymbolCount == 1)
    }

    @Test("Partial sale uses remaining shares and remaining cost")
    func partialSaleUsesRemaining() {
        let soldFirstLot = holding(soldSharesPerLot: [0: 400])
        let result = UnrealizedPnLCalculator.metrics(for: soldFirstLot, quote: quote(current: 130, previous: 125))

        #expect(result.totalQuantity == 1800)
        #expect((result.holdingResult ?? .zero).rounded(scale: 2) == 52965)
    }

    @Test("Empty portfolio totals")
    func emptyPortfolioTotals() {
        #expect(UnrealizedPnLCalculator.totals(from: []) == PortfolioTotals.empty)
    }
}

extension Decimal {
    func rounded(scale: Int) -> Decimal {
        var input = self
        var output = Decimal()
        NSDecimalRound(&output, &input, scale, .plain)
        return output
    }
}