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
        #expect(result.allocations[0].realizedResult == 130000 - 91425 - 575.25)
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