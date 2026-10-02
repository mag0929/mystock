import Foundation
import Testing
@testable import MyStock

@Suite("Holding aggregates and stock allocation")
struct HoldingAggregateTests {
    @Test("Creating a stock allocation lot")
    func creatingStockAllocationLot() {
        let lot = Lot(
            symbol: "2330",
            lotDate: Fixtures.makeDate(2026, 4, 1),
            quantity: 200,
            pricePerShare: 0,
            totalFees: 0,
            lotType: .stockAllocation
        )

        #expect(lot.lotType == .stockAllocation)
        #expect(lot.remainingQuantity == 200)
        #expect(lot.totalCost == 0)
        #expect(lot.totalFees == 0)
    }

    @Test("Stock allocation effect on a holding")
    func stockAllocationEffectOnHolding() {
        let first = Lot(symbol: "2330", lotDate: Fixtures.makeDate(2026, 1, 10), quantity: 1000, pricePerShare: 150)
        let second = Lot(symbol: "2330", lotDate: Fixtures.makeDate(2026, 2, 20), quantity: 1000, pricePerShare: 90)
        let allocation = Lot(
            symbol: "2330",
            lotDate: Fixtures.makeDate(2026, 4, 1),
            quantity: 200,
            pricePerShare: 0,
            lotType: .stockAllocation
        )

        let holding = HoldingCalculator.holdings(from: [first, second, allocation])[0]

        #expect(holding.totalQuantity == 2200)
        #expect(holding.totalRemainingCost == 240000)
        #expect((holding.averageCostPerShare ?? .zero).rounded(scale: 2) == Decimal(string: "109.09"))
    }

    @Test("Aggregate across mixed lot types")
    func aggregateAcrossMixedLotTypes() {
        let buyLot = Lot(symbol: "2330", lotDate: Fixtures.makeDate(2026, 1, 10), quantity: 2000, pricePerShare: 120)
        let allocation = Lot(
            symbol: "2330",
            lotDate: Fixtures.makeDate(2026, 4, 1),
            quantity: 200,
            pricePerShare: 0,
            lotType: .stockAllocation
        )

        let holding = HoldingCalculator.holdings(from: [buyLot, allocation])[0]

        #expect(holding.totalQuantity == 2200)
        #expect(holding.totalRemainingCost == 240000)
        #expect((holding.averageCostPerShare ?? .zero).rounded(scale: 2) == Decimal(string: "109.09"))
    }

    @Test("All shares sold")
    func allSharesSold() {
        let lot = Lot(symbol: "2330", lotDate: Fixtures.makeDate(2026, 1, 10), quantity: 1000, pricePerShare: 90)
        lot.remainingQuantity = 0

        let all = HoldingCalculator.holdings(from: [lot])
        let current = HoldingCalculator.currentHoldings(from: [lot])

        #expect(all.count == 1)
        #expect(all[0].totalQuantity == 0)
        #expect(all[0].averageCostPerShare == nil)
        #expect(current.isEmpty)
    }

    @Test("Sale allocation list contents")
    func saleAllocationListContents() {
        let lotAt90 = Lot(symbol: "2330", lotDate: Fixtures.makeDate(2026, 2, 20), quantity: 1000, pricePerShare: 90)
        let lotAt150 = Lot(symbol: "2330", lotDate: Fixtures.makeDate(2026, 1, 10), quantity: 1000, pricePerShare: 150)
        let allocation = Lot(
            symbol: "2330",
            lotDate: Fixtures.makeDate(2026, 4, 1),
            quantity: 200,
            pricePerShare: 0,
            lotType: .stockAllocation
        )

        let candidates = HoldingCalculator.saleAllocationCandidates(from: [lotAt90, lotAt150, allocation], symbol: "2330")

        #expect(candidates.count == 2)
        #expect(candidates.map(\.id).contains(allocation.id) == false)
        #expect(candidates.map(\.pricePerShare) == [150, 90])
    }

    @Test("A fully sold lot is not a sale allocation candidate")
    func soldLotExcluded() {
        let sold = Lot(symbol: "2330", lotDate: Fixtures.makeDate(2026, 1, 10), quantity: 1000, pricePerShare: 150)
        sold.remainingQuantity = 0

        #expect(HoldingCalculator.saleAllocationCandidates(from: [sold], symbol: "2330").isEmpty)
    }
}
