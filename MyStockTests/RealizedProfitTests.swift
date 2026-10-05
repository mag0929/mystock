import Foundation
import SwiftData
import Testing
@testable import MyStock

@MainActor
@Suite("Realized profit per allocated lot")
struct RealizedProfitTests {
    private struct Store {
        let container: ModelContainer
        let context: ModelContext
    }

    private func setUp() throws -> Store {
        let container = try Persistence.makeInMemoryContainer()
        return Store(container: container, context: ModelContext(container))
    }

    private var rates: FeeRates {
        FeeRates(commissionRate: Decimal(string: "0.001425") ?? .zero, transactionTaxRate: Decimal(string: "0.003") ?? .zero)
    }

    private func addLot(
        _ context: ModelContext,
        symbol: String = "2330",
        day: Int,
        month: Int = 2,
        price: Decimal,
        quantity: Int = 1000,
        fees: Decimal = 0,
        type: LotType = .buy
    ) -> Lot {
        let lot = Lot(
            symbol: symbol,
            lotDate: Fixtures.makeDate(2026, month, day),
            quantity: quantity,
            pricePerShare: price,
            totalFees: fees,
            lotType: type
        )
        context.insert(lot)
        return lot
    }

    @Test("Realized profit on a single allocation")
    func realizedProfitOnASingleAllocation() throws {
        let store = try setUp()
        let context = store.context
        let lot = addLot(context, day: 20, price: 90, fees: 1425)

        let sale = try SaleStore.save(
            symbol: "2330",
            saleDate: Fixtures.makeDate(2026, 3, 5),
            quantity: 1000,
            pricePerShare: 130,
            drafts: [DraftAllocation(lot: lot, quantity: 1000)],
            rates: rates,
            in: context
        )
        let allocations = try SaleStore.allocations(for: sale, in: context)
        let result = RealizedPnLCalculator.result(for: sale, allocations: allocations)

        #expect(result.allocations.count == 1)
        #expect(result.allocations[0].grossResult == 130000)
        #expect(result.allocations[0].lotCostPerShare == Decimal(string: "91.425"))
        #expect(result.allocations[0].realizedResult == Decimal(38000))
        #expect(result.realizedResult == result.allocations[0].realizedResult)
    }

    @Test("Allocation choice changes the reported split")
    func allocationChoiceChangesTheReportedSplit() throws {
        let store = try setUp()
        let context = store.context
        let dear = addLot(context, day: 10, price: 150)
        let cheap = addLot(context, day: 20, price: 90)

        let saleToCheap = try SaleStore.save(
            symbol: "2330",
            saleDate: Fixtures.makeDate(2026, 3, 5),
            quantity: 1000,
            pricePerShare: 130,
            drafts: [DraftAllocation(lot: cheap, quantity: 1000)],
            rates: rates,
            in: context
        )
        let cheapResult = RealizedPnLCalculator.result(
            for: saleToCheap,
            allocations: try SaleStore.allocations(for: saleToCheap, in: context)
        )
        let cheapRemaining = HoldingCalculator.holdings(from: [dear])[0].totalRemainingCost
        let cheapUnrealized = 130 * Decimal(dear.remainingQuantity) - cheapRemaining

        #expect(cheapResult.realizedResult == Decimal(40000) - cheapResult.totalDeductions)
        #expect(cheapRemaining == 150000)
        #expect(cheapUnrealized == -20000)

        let dearContext = ModelContext(store.container)
        let dear2 = addLot(dearContext, day: 10, price: 150)
        let cheap2 = addLot(dearContext, day: 20, price: 90)
        let saleToDear = try SaleStore.save(
            symbol: "2330",
            saleDate: Fixtures.makeDate(2026, 3, 5),
            quantity: 1000,
            pricePerShare: 130,
            drafts: [DraftAllocation(lot: dear2, quantity: 1000)],
            rates: rates,
            in: dearContext
        )
        let dearResult = RealizedPnLCalculator.result(
            for: saleToDear,
            allocations: try SaleStore.allocations(for: saleToDear, in: dearContext)
        )
        let dearRemaining = HoldingCalculator.holdings(from: [cheap2])[0].totalRemainingCost
        let dearUnrealized = 130 * Decimal(cheap2.remainingQuantity) - dearRemaining

        #expect(dearResult.realizedResult == Decimal(-20000) - dearResult.totalDeductions)
        #expect(dearRemaining == 90000)
        #expect(dearUnrealized == 40000)
    }

    @Test("Fees and taxes are split across allocations without loss")
    func deductionsSplitWithoutLoss() throws {
        let store = try setUp()
        let context = store.context
        let dear = addLot(context, day: 10, price: 150)
        let cheap = addLot(context, day: 20, price: 90)

        let sale = try SaleStore.save(
            symbol: "2330",
            saleDate: Fixtures.makeDate(2026, 3, 5),
            quantity: 1000,
            pricePerShare: 130,
            drafts: [DraftAllocation(lot: cheap, quantity: 400), DraftAllocation(lot: dear, quantity: 600)],
            rates: rates,
            in: context
        )
        let result = RealizedPnLCalculator.result(
            for: sale,
            allocations: try SaleStore.allocations(for: sale, in: context)
        )

        let deductionSum = result.allocations.reduce(Decimal.zero) { $0 + $1.allocatedDeductions }
        #expect(result.allocations.count == 2)
        #expect(deductionSum == result.totalDeductions)
        #expect(result.realizedResult == result.allocations.reduce(Decimal.zero) { $0 + $1.realizedResult })
    }

    @Test("A single allocation carries all of the deductions")
    func singleAllocationCarriesAllDeductions() throws {
        let store = try setUp()
        let context = store.context
        let lot = addLot(context, day: 20, price: 90)

        let sale = try SaleStore.save(
            symbol: "2330",
            saleDate: Fixtures.makeDate(2026, 3, 5),
            quantity: 1000,
            pricePerShare: 130,
            drafts: [DraftAllocation(lot: lot, quantity: 1000)],
            rates: rates,
            in: context
        )
        let result = RealizedPnLCalculator.result(
            for: sale,
            allocations: try SaleStore.allocations(for: sale, in: context)
        )

        #expect(result.allocations[0].allocatedDeductions == result.totalDeductions)
    }
}
@MainActor
@Suite("Realized profit proceeds, cost, and return")
struct RealizedProfitReturnTests {
    private func setUp() throws -> (ModelContainer, ModelContext) {
        let container = try Persistence.makeInMemoryContainer()
        return (container, ModelContext(container))
    }

    private var rates: FeeRates {
        FeeRates(commissionRate: Decimal(string: "0.001425") ?? .zero, transactionTaxRate: Decimal(string: "0.003") ?? .zero)
    }

    private func addLot(
        _ context: ModelContext,
        day: Int,
        price: Decimal,
        fees: Decimal = 0
    ) -> Lot {
        let lot = Lot(
            symbol: "2330",
            lotDate: Fixtures.makeDate(2026, 1, day),
            quantity: 1000,
            pricePerShare: price,
            totalFees: fees,
            lotType: .buy
        )
        context.insert(lot)
        return lot
    }

    private func result(
        for sale: Sale,
        in context: ModelContext
    ) throws -> SaleResult {
        RealizedPnLCalculator.result(for: sale, allocations: try SaleStore.allocations(for: sale, in: context))
    }

    @Test("Gross proceeds exclude commission and transaction tax")
    func grossProceedsExcludeFees() throws {
        let (_, context) = try setUp()
        let lot = addLot(context, day: 20, price: 90)
        let sale = try SaleStore.save(
            symbol: "2330",
            saleDate: Fixtures.makeDate(2026, 3, 5),
            quantity: 1000,
            pricePerShare: 130,
            drafts: [DraftAllocation(lot: lot, quantity: 1000)],
            rates: rates,
            in: context
        )
        let computed = try result(for: sale, in: context)

        #expect(computed.grossProceeds == 130000)
        #expect(computed.totalDeductions == 575)
        #expect(computed.realizedResult == computed.grossProceeds - computed.costBasis - computed.totalDeductions)
    }

    @Test("Cost basis is the cost of the allocated shares")
    func costBasisIsFeeInclusive() throws {
        let (_, context) = try setUp()
        let lot = addLot(context, day: 20, price: 90, fees: 1425)
        let sale = try SaleStore.save(
            symbol: "2330",
            saleDate: Fixtures.makeDate(2026, 3, 5),
            quantity: 1000,
            pricePerShare: 130,
            drafts: [DraftAllocation(lot: lot, quantity: 1000)],
            rates: rates,
            in: context
        )
        let computed = try result(for: sale, in: context)

        #expect(computed.costBasis == Decimal(string: "91425"))
    }

    @Test("Cost basis counts only the allocated shares")
    func costBasisCoversAllocatedSharesOnly() throws {
        let (_, context) = try setUp()
        let lot = addLot(context, day: 20, price: 90)
        let sale = try SaleStore.save(
            symbol: "2330",
            saleDate: Fixtures.makeDate(2026, 3, 5),
            quantity: 400,
            pricePerShare: 130,
            drafts: [DraftAllocation(lot: lot, quantity: 400)],
            rates: rates,
            in: context
        )
        let computed = try result(for: sale, in: context)

        #expect(computed.costBasis == 36000)
    }

    @Test("Return percentage is measured against the cost basis")
    func returnPercentageOverCostBasis() throws {
        let (_, context) = try setUp()
        let lot = addLot(context, day: 20, price: 90)
        let sale = try SaleStore.save(
            symbol: "2330",
            saleDate: Fixtures.makeDate(2026, 3, 5),
            quantity: 1000,
            pricePerShare: 130,
            drafts: [DraftAllocation(lot: lot, quantity: 1000)],
            rates: rates,
            in: context
        )
        let computed = try result(for: sale, in: context)

        let expected = computed.realizedResult / computed.costBasis
        #expect(computed.returnPercentage == expected)
        #expect(computed.returnPercentage! > 0)
    }

    @Test("A return over a zero cost basis is unavailable")
    func zeroCostBasisHasNoReturn() throws {
        let (_, context) = try setUp()
        let lot = addLot(context, day: 20, price: 90, fees: -90000)
        let sale = try SaleStore.save(
            symbol: "2330",
            saleDate: Fixtures.makeDate(2026, 3, 5),
            quantity: 1000,
            pricePerShare: 130,
            drafts: [DraftAllocation(lot: lot, quantity: 1000)],
            rates: rates,
            in: context
        )
        let computed = try result(for: sale, in: context)

        #expect(computed.costBasis <= 0)
        #expect(computed.returnPercentage == nil)
    }

    @Test("The allocation detail sums to the sale's realized profit")
    func allocationDetailSumsToRealizedProfit() throws {
        let (_, context) = try setUp()
        let cheap = addLot(context, day: 10, price: 90)
        let dear = addLot(context, day: 20, price: 150)
        let sale = try SaleStore.save(
            symbol: "2330",
            saleDate: Fixtures.makeDate(2026, 3, 5),
            quantity: 1000,
            pricePerShare: 130,
            drafts: [
                DraftAllocation(lot: cheap, quantity: 600),
                DraftAllocation(lot: dear, quantity: 400)
            ],
            rates: rates,
            in: context
        )
        let computed = try result(for: sale, in: context)

        #expect(computed.allocations.count == 2)
        #expect(computed.allocations[0].quantity == 600)
        #expect(computed.allocations[1].quantity == 400)
        #expect(computed.allocations[0].lotCostPerShare == 90)
        #expect(computed.allocations[1].lotCostPerShare == 150)
        #expect(computed.allocations[0].salePricePerShare == 130)
        let sum = computed.allocations.reduce(Decimal.zero) { $0 + $1.realizedResult }
        #expect(sum == computed.realizedResult)
        #expect(computed.costBasis == 114000)
    }

    @Test("A period summary sums its sales rather than averaging their returns")
    func periodSummarySumsItsSales() throws {
        let (_, context) = try setUp()
        let cheap = addLot(context, day: 10, price: 90)
        let dear = addLot(context, day: 20, price: 150)

        _ = try SaleStore.save(
            symbol: "2330",
            saleDate: Fixtures.makeDate(2026, 3, 5),
            quantity: 1000,
            pricePerShare: 130,
            drafts: [DraftAllocation(lot: cheap, quantity: 1000)],
            rates: rates,
            in: context
        )
        _ = try SaleStore.save(
            symbol: "2330",
            saleDate: Fixtures.makeDate(2026, 3, 20),
            quantity: 1000,
            pricePerShare: 140,
            drafts: [DraftAllocation(lot: dear, quantity: 1000)],
            rates: rates,
            in: context
        )

        let sales = try context.fetch(FetchDescriptor<Sale>())
        var allocations: [UUID: [SaleAllocation]] = [:]
        for sale in sales {
            allocations[sale.id] = try SaleStore.allocations(for: sale, in: context)
        }
        let query = RealizedQueryService.run(
            period: .currentMonth,
            sales: sales,
            allocationsBySaleID: allocations,
            now: Fixtures.makeDate(2026, 3, 25)
        )

        #expect(query.saleCount == 2)
        #expect(query.grossProceedsTotal == 270000)
        #expect(query.costBasisTotal == 240000)
        #expect(query.realizedTotal == query.sales.reduce(Decimal.zero) { $0 + $1.realizedResult })
        // 40000 - 185 - 390, then -10000 - 199 - 420.
        #expect(query.realizedTotal == 28806)
        #expect(query.returnPercentage == query.realizedTotal / query.costBasisTotal)
        #expect(Format.percent(query.returnPercentage!) == "+12.00%")
    }

    @Test("A symbol group reports its own proceeds, cost, and return")
    func symbolGroupFigures() throws {
        let (_, context) = try setUp()
        let lot = addLot(context, day: 20, price: 90)
        _ = try SaleStore.save(
            symbol: "2330",
            saleDate: Fixtures.makeDate(2026, 3, 5),
            quantity: 1000,
            pricePerShare: 130,
            drafts: [DraftAllocation(lot: lot, quantity: 1000)],
            rates: rates,
            in: context
        )

        let sales = try context.fetch(FetchDescriptor<Sale>())
        var allocations: [UUID: [SaleAllocation]] = [:]
        for sale in sales {
            allocations[sale.id] = try SaleStore.allocations(for: sale, in: context)
        }
        let query = RealizedQueryService.run(
            period: .currentMonth,
            sales: sales,
            allocationsBySaleID: allocations,
            now: Fixtures.makeDate(2026, 3, 25)
        )

        let group = try #require(query.bySymbol.first)
        #expect(group.symbol == "2330")
        #expect(group.grossProceedsTotal == 130000)
        #expect(group.costBasisTotal == 90000)
        #expect(group.returnPercentage == group.realizedTotal / group.costBasisTotal)
    }

    @Test("A period with no sales has no return percentage")
    func emptyPeriodHasNoReturn() throws {
        let (_, context) = try setUp()
        let query = RealizedQueryService.run(
            period: .currentMonth,
            sales: [],
            allocationsBySaleID: [:],
            now: Fixtures.makeDate(2026, 3, 25)
        )

        #expect(query.saleCount == 0)
        #expect(query.returnPercentage == nil)
        #expect(query.bySymbol.isEmpty)
    }
}
