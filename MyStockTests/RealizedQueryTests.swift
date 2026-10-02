import Foundation
import SwiftData
import Testing
@testable import MyStock

@MainActor
@Suite("Realized profit query periods")
struct RealizedQueryTests {
    private struct Store {
        let container: ModelContainer
        let context: ModelContext
    }

    private func setUp() throws -> Store {
        let container = try Persistence.makeInMemoryContainer()
        return Store(container: container, context: ModelContext(container))
    }

    private var zeroRates: FeeRates {
        FeeRates(commissionRate: .zero, transactionTaxRate: .zero)
    }

    @discardableResult
    private func sell(
        _ context: ModelContext,
        symbol: String = "2330",
        lotDay: Int,
        lotPrice: Decimal,
        saleMonth: Int,
        saleDay: Int,
        salePrice: Decimal,
        quantity: Int = 1000,
        rates: FeeRates? = nil
    ) throws -> Sale {
        let lot = Lot(
            symbol: symbol,
            lotDate: Fixtures.makeDate(2026, lotDay < 20 ? 1 : 2, lotDay),
            quantity: quantity,
            pricePerShare: lotPrice
        )
        context.insert(lot)
        let sale = try SaleStore.save(
            symbol: symbol,
            saleDate: Fixtures.makeDate(2026, saleMonth, saleDay),
            quantity: quantity,
            pricePerShare: salePrice,
            drafts: [DraftAllocation(lot: lot, quantity: quantity)],
            rates: rates ?? zeroRates,
            in: context
        )
        try context.save()
        return sale
    }

    private func allocationsBySale(_ context: ModelContext) throws -> [UUID: [SaleAllocation]] {
        var map: [UUID: [SaleAllocation]] = [:]
        for sale in try context.fetch(FetchDescriptor<Sale>()) {
            map[sale.id] = try SaleStore.allocations(for: sale, in: context)
        }
        return map
    }

    @Test("Querying today's realized profit")
    func queryingTodaysRealizedProfit() throws {
        let store = try setUp()
        let context = store.context
        try sell(context, lotDay: 10, lotPrice: 100, saleMonth: 3, saleDay: 5, salePrice: 105)
        try sell(context, lotDay: 12, lotPrice: 100, saleMonth: 3, saleDay: 5, salePrice: 98)

        let result = RealizedQueryService.run(
            period: .today,
            sales: try context.fetch(FetchDescriptor<Sale>()),
            allocationsBySaleID: try allocationsBySale(context),
            now: Fixtures.makeDate(2026, 3, 5)
        )

        #expect(result.saleCount == 2)
        #expect(result.realizedTotal == 3000)
    }

    @Test("Querying the current month")
    func queryingCurrentMonth() throws {
        let store = try setUp()
        let context = store.context
        try sell(context, lotDay: 10, lotPrice: 100, saleMonth: 3, saleDay: 5, salePrice: 105)
        try sell(context, lotDay: 12, lotPrice: 100, saleMonth: 2, saleDay: 15, salePrice: 110)

        let result = RealizedQueryService.run(
            period: .currentMonth,
            sales: try context.fetch(FetchDescriptor<Sale>()),
            allocationsBySaleID: try allocationsBySale(context),
            now: Fixtures.makeDate(2026, 3, 20)
        )

        #expect(result.saleCount == 1)
        #expect(result.realizedTotal == 5000)
    }

    @Test("Querying the previous three months")
    func queryingPreviousThreeMonths() throws {
        let store = try setUp()
        let context = store.context
        try sell(context, lotDay: 10, lotPrice: 100, saleMonth: 1, saleDay: 10, salePrice: 110)
        try sell(context, lotDay: 12, lotPrice: 100, saleMonth: 2, saleDay: 15, salePrice: 115)
        try sell(context, lotDay: 14, lotPrice: 100, saleMonth: 3, saleDay: 5, salePrice: 120)

        let result = RealizedQueryService.run(
            period: .previousThreeMonths,
            sales: try context.fetch(FetchDescriptor<Sale>()),
            allocationsBySaleID: try allocationsBySale(context),
            now: Fixtures.makeDate(2026, 3, 10)
        )

        #expect(result.saleCount == 3)
        #expect(result.realizedTotal == 45000)
    }

    @Test("Previous three months excludes the month before the window")
    func previousThreeMonthsExcludesEarlierMonths() throws {
        let store = try setUp()
        let context = store.context
        try sell(context, lotDay: 10, lotPrice: 100, saleMonth: 1, saleDay: 10, salePrice: 110)

        let result = RealizedQueryService.run(
            period: .previousThreeMonths,
            sales: try context.fetch(FetchDescriptor<Sale>()),
            allocationsBySaleID: try allocationsBySale(context),
            now: Fixtures.makeDate(2026, 5, 10)
        )

        #expect(result.saleCount == 0)
        #expect(result.realizedTotal == 0)
    }

    @Test("Querying a custom range")
    func queryingACustomRange() throws {
        let store = try setUp()
        let context = store.context
        try sell(context, lotDay: 10, lotPrice: 100, saleMonth: 1, saleDay: 10, salePrice: 110)
        try sell(context, lotDay: 12, lotPrice: 100, saleMonth: 2, saleDay: 15, salePrice: 115)
        try sell(context, lotDay: 14, lotPrice: 100, saleMonth: 3, saleDay: 5, salePrice: 120)

        let result = RealizedQueryService.run(
            period: .custom(from: Fixtures.makeDate(2026, 2, 1), to: Fixtures.makeDate(2026, 2, 28)),
            sales: try context.fetch(FetchDescriptor<Sale>()),
            allocationsBySaleID: try allocationsBySale(context),
            now: Fixtures.makeDate(2026, 3, 10)
        )

        #expect(result.saleCount == 1)
        #expect(result.realizedTotal == 15000)
    }

    @Test("Period with no sales")
    func periodWithNoSales() throws {
        let store = try setUp()
        let context = store.context

        let result = RealizedQueryService.run(
            period: .today,
            sales: try context.fetch(FetchDescriptor<Sale>()),
            allocationsBySaleID: try allocationsBySale(context),
            now: Fixtures.makeDate(2026, 3, 5)
        )

        #expect(result.saleCount == 0)
        #expect(result.realizedTotal == 0)
        #expect(result.commissionTotal == 0)
        #expect(result.transactionTaxTotal == 0)
        #expect(result.bySymbol.isEmpty)
    }

    @Test("Query reports the fees and tax deducted")
    func queryReportsDeductions() throws {
        let store = try setUp()
        let context = store.context
        try sell(
            context,
            lotDay: 10,
            lotPrice: 100,
            saleMonth: 3,
            saleDay: 5,
            salePrice: 130,
            rates: FeeRates(commissionRate: Decimal(string: "0.001425") ?? .zero, transactionTaxRate: Decimal(string: "0.003") ?? .zero)
        )

        let result = RealizedQueryService.run(
            period: .today,
            sales: try context.fetch(FetchDescriptor<Sale>()),
            allocationsBySaleID: try allocationsBySale(context),
            now: Fixtures.makeDate(2026, 3, 5)
        )

        #expect(result.commissionTotal == 185)
        #expect(result.transactionTaxTotal == 390)
        #expect(result.securitiesTransactionTaxReferenceTotal == 520)
        #expect(result.totalDeductions == 575)
        #expect(result.realizedTotal == Decimal(30000) - 575)
    }

    @Test("Grouping by symbol")
    func groupingBySymbol() throws {
        let store = try setUp()
        let context = store.context
        try sell(context, symbol: "2330", lotDay: 10, lotPrice: 100, saleMonth: 3, saleDay: 5, salePrice: 105)
        try sell(context, symbol: "2330", lotDay: 12, lotPrice: 100, saleMonth: 3, saleDay: 20, salePrice: 98)
        try sell(context, symbol: "2317", lotDay: 14, lotPrice: 50, saleMonth: 3, saleDay: 25, salePrice: 60)

        let result = RealizedQueryService.run(
            period: .custom(from: Fixtures.makeDate(2026, 3, 1), to: Fixtures.makeDate(2026, 3, 31)),
            sales: try context.fetch(FetchDescriptor<Sale>()),
            allocationsBySaleID: try allocationsBySale(context),
            now: Fixtures.makeDate(2026, 3, 31)
        )

        let group = result.bySymbol.first { $0.symbol == "2330" }
        #expect(result.bySymbol.count == 2)
        #expect(group?.saleCount == 2)
        #expect(group?.realizedTotal == 3000)
        #expect(group?.quantitySold == 2000)
        #expect(result.bySymbol.first { $0.symbol == "2317" }?.realizedTotal == 10000)
        #expect(result.realizedTotal == 13000)
    }

    @Test("Each sale entry shows its allocations")
    func eachSaleEntryShowsAllocations() throws {
        let store = try setUp()
        let context = store.context
        let cheap = Lot(symbol: "2330", lotDate: Fixtures.makeDate(2026, 1, 20), quantity: 1000, pricePerShare: 100)
        let dear = Lot(symbol: "2330", lotDate: Fixtures.makeDate(2026, 1, 10), quantity: 1000, pricePerShare: 120)
        context.insert(cheap)
        context.insert(dear)
        try SaleStore.save(
            symbol: "2330",
            saleDate: Fixtures.makeDate(2026, 3, 5),
            quantity: 1000,
            pricePerShare: 110,
            drafts: [DraftAllocation(lot: cheap, quantity: 400), DraftAllocation(lot: dear, quantity: 600)],
            rates: zeroRates,
            in: context
        )

        let result = RealizedQueryService.run(
            period: .today,
            sales: try context.fetch(FetchDescriptor<Sale>()),
            allocationsBySaleID: try allocationsBySale(context),
            now: Fixtures.makeDate(2026, 3, 5)
        )
        let entry = result.sales[0]

        #expect(entry.symbol == "2330")
        #expect(entry.quantity == 1000)
        #expect(entry.pricePerShare == 110)
        #expect(entry.allocations.count == 2)
        #expect(entry.allocations.map(\.lotDate) == [Fixtures.makeDate(2026, 1, 10), Fixtures.makeDate(2026, 1, 20)])
        #expect(entry.allocations.map(\.quantity) == [600, 400])
        #expect(entry.allocations.map(\.realizedResult) == [-6000, 4000])
        #expect(entry.realizedResult == -2000)
        #expect(entry.realizedResult == entry.allocations.reduce(Decimal.zero) { $0 + $1.realizedResult })
    }
}