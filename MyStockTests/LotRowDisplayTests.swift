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
        #expect(row.feesText == "—")
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
        #expect(row.feesText == "1,425")
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

        #expect(LotRowViewModel(lot: lot).feesText == "92")
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

        #expect(LotRowViewModel(lot: lot).feesText == "213.75")
    }
}
