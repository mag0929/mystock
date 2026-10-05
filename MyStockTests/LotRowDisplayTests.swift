import Foundation
import Testing
@testable import MyStock

@Suite("Per-lot display with type indicator")
struct LotRowDisplayTests {
    @Test("Displaying a stock allocation lot")
    func displayingStockAllocationLot() {
        let lot = Lot(
            symbol: "2330",
            lotDate: Fixtures.makeDate(2026, 4, 1),
            quantity: 200,
            pricePerShare: 0,
            totalFees: 0,
            lotType: .stockAllocation
        )

        let row = LotRowViewModel(lot: lot)

        #expect(row.typeText == "配股")
        #expect(row.quantityText == "200")
        #expect(row.remainingText == "200")
        #expect(row.costFieldsAvailable == false)
        #expect(row.pricePerShareText == "—")
        #expect(row.commissionText == "—")
    }

    @Test("Displaying a buy lot shows its costs")
    func displayingBuyLot() {
        let lot = Lot(
            symbol: "2330",
            lotDate: Fixtures.makeDate(2026, 1, 10),
            quantity: 1000,
            pricePerShare: 150,
            totalFees: 1425
        )

        let row = LotRowViewModel(lot: lot)

        #expect(row.typeText == "買進")
        #expect(row.costFieldsAvailable == true)
        #expect(row.pricePerShareText == "150.00")
        #expect(row.commissionText == "1,425")
        #expect(row.remainingText == "1,000")
    }

    @Test("A whole dollar fee shows without decimals")
    func wholeDollarFeeHasNoDecimals() {
        let lot = Lot(
            symbol: "8046",
            lotDate: Fixtures.makeDate(2026, 3, 2),
            quantity: 50,
            pricePerShare: 1300,
            totalFees: 92
        )

        #expect(LotRowViewModel(lot: lot).commissionText == "92")
    }

    @Test("A fee with a fractional part keeps its decimals")
    func fractionalFeeKeepsDecimals() {
        let lot = Lot(
            symbol: "2330",
            lotDate: Fixtures.makeDate(2026, 1, 10),
            quantity: 1000,
            pricePerShare: 150,
            totalFees: Decimal(string: "213.75") ?? .zero
        )

        #expect(LotRowViewModel(lot: lot).commissionText == "213.75")
    }
}

@Suite("Lot row purchase figures against current value")
struct LotRowValuationTests {
    private let rates = FeeRates(
        commissionRate: Decimal(string: "0.001425") ?? .zero,
        transactionTaxRate: Decimal(string: "0.003") ?? .zero
    )

    private func quote(_ price: Decimal) -> Quote {
        Quote(symbol: "2303", currentPrice: price, previousClose: price, source: .yahooFinance, isFallback: false)
    }

    private func buyLot(quantity: Int, price: Decimal, day: Int, month: Int = 7) -> Lot {
        return Lot(
            symbol: "2303",
            lotDate: Fixtures.makeDate(2026, month, day),
            quantity: quantity,
            pricePerShare: price,
            commission: FeeSettings.buyCommission(
                quantity: quantity,
                pricePerShare: price,
                rate: rates.commissionRate
            ),
            transactionTax: .zero,
            lotType: .buy
        )
    }

    @Test("A lot row reports the purchase price and what it is worth now")
    func lotRowShowsPurchaseAndCurrentFigures() {
        let lot = buyLot(quantity: 200, price: Decimal(string: "141.5") ?? .zero, day: 14)
        let metrics = LotPnLCalculator.metrics(for: lot, quote: quote(Decimal(string: "152.5") ?? .zero), rates: rates)
        let row = LotRowViewModel(lot: lot, metrics: metrics)

        #expect(row.pricePerShareText == "141.50")
        #expect(row.commissionText == "40")
        #expect(row.remainingCostText == "28,340")
        #expect(row.currentPriceText == "152.50")
        #expect(row.marketValueText == "30,500")
        #expect(row.resultText == "+2,026")
        #expect(row.returnText == "+7.15%")
    }

    @Test("The three worked examples hold")
    func threeWorkedExamples() {
        let cases: [(Int, Decimal, Int, String, String, String)] = [
            (200, Decimal(string: "141.5") ?? .zero, 14, "28,340", "+2,026", "+7.15%"),
            (100, Decimal(string: "130") ?? .zero, 20, "13,018", "+2,166", "+16.64%"),
            (200, Decimal(string: "117") ?? .zero, 7, "23,433", "+6,933", "+29.59%")
        ]
        for (quantity, price, day, cost, result, percentage) in cases {
            let lot = buyLot(quantity: quantity, price: price, day: day, month: day == 7 ? 8 : 7)
            let metrics = LotPnLCalculator.metrics(for: lot, quote: quote(Decimal(string: "152.5") ?? .zero), rates: rates)
            let row = LotRowViewModel(lot: lot, metrics: metrics)
            #expect(row.remainingCostText == cost)
            #expect(row.resultText == result)
            #expect(row.returnText == percentage)
        }
    }

    @Test("A partly sold lot is valued on the shares that remain")
    func partlySoldLotUsesRemainingShares() {
        let lot = buyLot(quantity: 200, price: Decimal(string: "141.5") ?? .zero, day: 14)
        lot.remainingQuantity = 100

        let metrics = LotPnLCalculator.metrics(for: lot, quote: quote(Decimal(string: "152.5") ?? .zero), rates: rates)

        #expect(metrics.marketValue == 15250)
        // Half the cost remains, and half the estimated sale fees.
        #expect(metrics.remainingCost == Decimal(string: "14170"))
        #expect(metrics.estimatedSaleFees == 66)
        #expect(metrics.result == Decimal(string: "1014"))
        #expect(metrics.returnPercentage! > 0)
    }

    @Test("A fully sold lot reports no unrealized result")
    func fullySoldLotHasNoUnrealizedResult() {
        let lot = buyLot(quantity: 200, price: Decimal(string: "141.5") ?? .zero, day: 14)
        lot.remainingQuantity = 0

        let metrics = LotPnLCalculator.metrics(for: lot, quote: quote(Decimal(string: "152.5") ?? .zero), rates: rates)

        // Reporting a result here would count the sold profit twice, since it
        // is already in realized profit.
        #expect(metrics.marketValue == nil)
        #expect(metrics.result == nil)
        #expect(metrics.returnPercentage == nil)
    }

    @Test("Without a price the row reports unavailable rather than zero")
    func noPriceIsUnavailable() {
        let lot = buyLot(quantity: 200, price: Decimal(string: "141.5") ?? .zero, day: 14)
        let metrics = LotPnLCalculator.metrics(for: lot, quote: nil, rates: rates)
        let row = LotRowViewModel(lot: lot, metrics: metrics)

        #expect(row.currentPriceText == "不可用")
        #expect(row.marketValueText == "不可用")
        #expect(row.resultText == "不可用")
        #expect(row.returnText == "不可用")
    }

    @Test("A stock allocation lot keeps its dashes")
    func allocationLotKeepsDashes() {
        let lot = Lot(
            symbol: "2303",
            lotDate: Fixtures.makeDate(2026, 8, 7),
            quantity: 200,
            pricePerShare: 0,
            totalFees: 0,
            lotType: .stockAllocation
        )
        let metrics = LotPnLCalculator.metrics(for: lot, quote: quote(Decimal(string: "152.5") ?? .zero), rates: rates)
        let row = LotRowViewModel(lot: lot, metrics: metrics)

        #expect(row.costFieldsAvailable == false)
        #expect(row.pricePerShareText == "—")
    }

    @Test("The lot row carries the stored company name")
    func lotRowCarriesName() {
        let lot = buyLot(quantity: 200, price: Decimal(string: "141.5") ?? .zero, day: 14)
        let metrics = LotPnLCalculator.metrics(for: lot, quote: quote(Decimal(string: "152.5") ?? .zero), rates: rates)
        let row = LotRowViewModel(lot: lot, displayName: "聯電", metrics: metrics)

        #expect(row.symbol == "2303")
        #expect(row.displayName == "聯電")
    }
}

@Suite("Unrealized profit nets the estimated sale fees")
struct UnrealizedNetOfSaleFeesTests {
    private let rates = FeeRates(
        commissionRate: Decimal(string: "0.001425") ?? .zero,
        transactionTaxRate: Decimal(string: "0.003") ?? .zero
    )

    @Test("The estimated sale fees truncate like a real sale")
    func estimatedFeesTruncate() {
        let fees = FeeSettings.estimatedSaleFees(
            quantity: 200,
            pricePerShare: Decimal(string: "152.5") ?? .zero,
            rates: rates
        )
        #expect(fees.commission == 43)
        #expect(fees.transactionTax == 91)
        #expect(fees.total == 134)
    }

    @Test("A holding result is net of the fees a sale would incur")
    func holdingResultIsNet() {
        let lot = Lot(
            symbol: "2303",
            lotDate: Fixtures.makeDate(2026, 7, 14),
            quantity: 200,
            pricePerShare: Decimal(string: "141.5") ?? .zero,
            commission: 40,
            transactionTax: .zero,
            lotType: .buy
        )
        var holding = HoldingCalculator.currentHoldings(from: [lot])[0]
        holding.displayName = "聯電"

        let metrics = UnrealizedPnLCalculator.metrics(
            for: holding,
            quote: Quote(symbol: "2303", currentPrice: Decimal(string: "152.5") ?? .zero, previousClose: 150, source: .yahooFinance, isFallback: false),
            rates: rates
        )

        // 30500 market value - 28340 cost - 134 estimated fees.
        #expect(metrics.estimatedSaleFees == 134)
        #expect(metrics.holdingResult == 2026)
        #expect(metrics.holdingReturnPercentage! > 0)
    }

    @Test("A lot row and its holding row agree on the same figure")
    func lotAndHoldingAgree() {
        let lot = Lot(
            symbol: "2303",
            lotDate: Fixtures.makeDate(2026, 7, 14),
            quantity: 200,
            pricePerShare: Decimal(string: "141.5") ?? .zero,
            commission: 40,
            transactionTax: .zero,
            lotType: .buy
        )
        let holding = HoldingCalculator.currentHoldings(from: [lot])[0]
        let quote = Quote(symbol: "2303", currentPrice: Decimal(string: "152.5") ?? .zero, previousClose: 150, source: .yahooFinance, isFallback: false)

        let holdingResult = UnrealizedPnLCalculator.metrics(for: holding, quote: quote, rates: rates).holdingResult
        let lotResult = LotPnLCalculator.metrics(for: lot, quote: quote, rates: rates).result

        // The user asked for one profit figure; two screens showing two
        // different ones for the same shares would be a defect.
        #expect(holdingResult == lotResult)
    }
}
