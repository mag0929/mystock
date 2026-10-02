import Foundation
import Testing
@testable import MyStock

@Suite("Lot data model")
struct LotDataModelTests {
    @Test("Recording a purchase")
    func recordingAPurchase() {
        let lot = Lot(
            symbol: "2330",
            lotDate: Fixtures.makeDate(2026, 1, 10),
            quantity: 1000,
            pricePerShare: 150,
            totalFees: 1425
        )

        #expect(lot.symbol == "2330")
        #expect(lot.lotType == .buy)
        #expect(lot.remainingQuantity == 1000)
        #expect(lot.totalCost == Decimal(150000) + Decimal(1425))
    }

    @Test("Lot cost includes fees")
    func lotCostIncludesFees() throws {
        let expected: [(quantity: Int, price: Decimal, fees: Decimal, total: Decimal)] = [
            (1000, Decimal(150), Decimal(1425), Decimal(151425)),
            (1000, Decimal(90), Decimal(1425), Decimal(91425)),
            (200, Decimal(string: "109.09")!, Decimal.zero, Decimal(21818)),
        ]

        for row in expected {
            let lot = Lot(
                symbol: "2330",
                lotDate: Fixtures.makeDate(2026, 1, 10),
                quantity: row.quantity,
                pricePerShare: row.price,
                totalFees: row.fees
            )
            #expect(lot.totalCost == row.total, "quantity \(row.quantity)")
        }
    }

    @Test("Remaining cost follows remaining quantity")
    func remainingCost() {
        let lot = Lot(
            symbol: "2330",
            lotDate: Fixtures.makeDate(2026, 1, 10),
            quantity: 1000,
            pricePerShare: 100,
            totalFees: 0
        )
        lot.remainingQuantity = 400

        #expect(lot.remainingCost == 40000)
        #expect(lot.costPerShare == 100)
    }

    @Test("A stock allocation lot has zero cost")
    func stockAllocationHasZeroCost() {
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
        #expect(lot.isAllocatableForSale == false)
    }

    @Test("Only buy lots with shares left can be allocated to a sale")
    func allocatableForSale() {
        let buy = Lot(
            symbol: "2330",
            lotDate: Fixtures.makeDate(2026, 1, 10),
            quantity: 1000,
            pricePerShare: 90,
            totalFees: 0
        )
        #expect(buy.isAllocatableForSale == true)

        buy.remainingQuantity = 0
        #expect(buy.isAllocatableForSale == false)
    }
}
