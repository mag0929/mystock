import Foundation
import SwiftData
import Testing
@testable import MyStock

@MainActor
@Suite("Fee and tax handling on sales")
struct SaleFeeTests {
    private struct Store {
        let container: ModelContainer
        let context: ModelContext
    }

    private func setUp() throws -> Store {
        let container = try Persistence.makeInMemoryContainer()
        return Store(container: container, context: ModelContext(container))
    }

    private var standardRates: FeeRates {
        FeeRates(commissionRate: Decimal(string: "0.001425") ?? .zero, transactionTaxRate: Decimal(string: "0.003") ?? .zero)
    }

    @discardableResult
    private func recordSale(
        in context: ModelContext,
        rates: FeeRates,
        quantity: Int = 1000,
        price: Decimal = 130
    ) throws -> Sale {
        let lot = Lot(symbol: "2330", lotDate: Fixtures.makeDate(2026, 1, 10), quantity: quantity, pricePerShare: 100)
        context.insert(lot)
        return try SaleStore.save(
            symbol: "2330",
            saleDate: Fixtures.makeDate(2026, 3, 5),
            quantity: quantity,
            pricePerShare: price,
            drafts: [DraftAllocation(lot: lot, quantity: quantity)],
            rates: rates,
            in: context
        )
    }

    @Test("Sale fees and taxes")
    func saleFeesAndTaxes() throws {
        let store = try setUp()
        let sale = try recordSale(in: store.context, rates: standardRates)

        #expect(sale.grossProceeds == 130000)
        #expect(sale.commission == 185, "130000 × 0.001425 = 185.25，無條捨去為 185")
        #expect(sale.transactionTax == 390)
        #expect(sale.securitiesTransactionTaxReference == 520)
        #expect(sale.totalDeductions == 575)
    }

    @Test("Sale commission and tax are truncated to whole dollars")
    func saleFeesTruncateToWholeDollars() throws {
        let store = try setUp()
        let sale = try recordSale(
            in: store.context,
            rates: standardRates,
            quantity: 50,
            price: 1300
        )

        #expect(sale.grossProceeds == 65000)
        #expect(sale.commission == 92, "65000 × 0.001425 = 92.625，無條捨去為 92")
        #expect(sale.transactionTax == 195, "65000 × 0.003 = 195")
        #expect(sale.totalDeductions == 287)
        // Bought at 100, so cost is 5000: 65000 − 5000 − 287.
        #expect(RealizedPnLCalculator.result(
            for: sale,
            allocations: try SaleStore.allocations(for: sale, in: store.context)
        ).realizedResult == Decimal(59713))
    }

    @Test("Commission and transaction tax are deducted from realized profit")
    func deductionsComeOutOfRealizedProfit() throws {
        let store = try setUp()
        let context = store.context
        let sale = try recordSale(in: context, rates: standardRates)
        let result = RealizedPnLCalculator.result(
            for: sale,
            allocations: try SaleStore.allocations(for: sale, in: context)
        )

        #expect(result.realizedResult == Decimal(30000) - 575)
    }

    @Test("Securities transaction tax is recorded but not deducted")
    func securitiesTransactionTaxIsNotDeducted() throws {
        let store = try setUp()
        let context = store.context
        let sale = try recordSale(in: context, rates: standardRates)

        #expect(sale.securitiesTransactionTaxReference == 520)
        #expect(sale.totalDeductions == sale.commission + sale.transactionTax)
        #expect(sale.totalDeductions != sale.commission + sale.transactionTax + sale.securitiesTransactionTaxReference)
    }

    @Test("Commission rate change does not alter past sales")
    func commissionRateChangeDoesNotAlterPastSales() throws {
        let store = try setUp()
        let context = store.context
        let sale = try recordSale(in: context, rates: standardRates)
        let commissionBefore = sale.commission

        try FeeSettingsStore.update(
            commissionRate: Decimal(string: "0.0015") ?? .zero,
            transactionTaxRate: Decimal(string: "0.003") ?? .zero,
            in: context
        )
        let ratesAfterChange = try FeeSettingsStore.currentRates(in: context)
        let laterSale = try recordSale(in: context, rates: ratesAfterChange, price: 200)

        #expect(sale.commission == commissionBefore)
        #expect(sale.commission == 185, "130000 × 0.001425 = 185.25，無條捨去為 185")
        #expect(laterSale.commission == 300)
        #expect(ratesAfterChange.commissionRate == Decimal(string: "0.0015"))
    }

    @Test("Transaction tax rate change does not alter past sales")
    func transactionTaxRateChangeDoesNotAlterPastSales() throws {
        let store = try setUp()
        let context = store.context
        let sale = try recordSale(in: context, rates: standardRates)

        try FeeSettingsStore.update(
            commissionRate: Decimal(string: "0.001425") ?? .zero,
            transactionTaxRate: Decimal(string: "0.005") ?? .zero,
            in: context
        )
        let ratesAfterChange = try FeeSettingsStore.currentRates(in: context)
        let laterSale = try recordSale(in: context, rates: ratesAfterChange, price: 200)

        #expect(sale.transactionTax == 390)
        #expect(laterSale.transactionTax == 1000)
    }
}