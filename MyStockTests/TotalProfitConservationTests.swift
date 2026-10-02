import Foundation
import SwiftData
import Testing
@testable import MyStock

@MainActor
@Suite("Total profit conservation")
struct TotalProfitConservationTests {
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

    private func addBuyLot(
        _ context: ModelContext,
        day: Int,
        price: Decimal,
        quantity: Int = 1000,
        fees: Decimal = 0
    ) -> Lot {
        let lot = Lot(
            symbol: "2330",
            lotDate: Fixtures.makeDate(2026, 1, day),
            quantity: quantity,
            pricePerShare: price,
            totalFees: fees
        )
        context.insert(lot)
        return lot
    }

    private struct Run {
        let realized: Decimal
        let saleDeductions: Decimal
        let unrealized: Decimal
        let remainingQuantity: Int
        let remainingCost: Decimal

        var totalBeforeSaleCosts: Decimal { realized + saleDeductions + unrealized }

        var remainingMarketValue: Decimal { unrealized + remainingCost }
    }

    private func saleDeductionsTotal(_ context: ModelContext) -> Decimal {
        (try? context.fetch(FetchDescriptor<Sale>()))?.reduce(Decimal.zero) { $0 + $1.totalDeductions } ?? .zero
    }

    private func makeRun(
        targetPrice: Decimal,
        targetDay: Int = 10,
        fees: Decimal = 0
    ) throws -> Run {
        let store = try setUp()
        let context = store.context
        let target = addBuyLot(context, day: targetDay, price: targetPrice, fees: fees)
        let otherPrice: Decimal = targetPrice == 150 ? 90 : 150
        let other = addBuyLot(context, day: targetPrice == 150 ? 20 : 10, price: otherPrice, fees: fees)

        let sale = try SaleStore.save(
            symbol: "2330",
            saleDate: Fixtures.makeDate(2026, 3, 5),
            quantity: 1000,
            pricePerShare: 130,
            drafts: [DraftAllocation(lot: target, quantity: 1000)],
            rates: rates,
            in: context
        )
        let result = RealizedPnLCalculator.result(
            for: sale,
            allocations: try SaleStore.allocations(for: sale, in: context)
        )
        let holding = HoldingCalculator.currentHoldings(from: [target, other])[0]
        return Run(
            realized: result.realizedResult,
            saleDeductions: result.totalDeductions,
            unrealized: Decimal(130) * Decimal(holding.totalQuantity) - holding.totalRemainingCost,
            remainingQuantity: holding.totalQuantity,
            remainingCost: holding.totalRemainingCost
        )
    }

    @Test("Total is independent of allocation")
    func totalIsIndependentOfAllocation() throws {
        let toCheapLot = try makeRun(targetPrice: 90, targetDay: 20)
        let toDearLot = try makeRun(targetPrice: 150, targetDay: 10)

        #expect(toCheapLot.realized == 40000 - toCheapLot.saleDeductions)
        #expect(toCheapLot.unrealized == -20000)
        #expect(toDearLot.realized == -20000 - toDearLot.saleDeductions)
        #expect(toDearLot.unrealized == 40000)
        #expect(toCheapLot.realized + toCheapLot.unrealized == toDearLot.realized + toDearLot.unrealized)
        #expect(toCheapLot.realized + toCheapLot.saleDeductions + toCheapLot.unrealized == 20000)
        #expect(toCheapLot.realized + toCheapLot.unrealized == 20000 - toCheapLot.saleDeductions)
        #expect(toDearLot.realized + toDearLot.unrealized == 20000 - toDearLot.saleDeductions)
    }

    @Test("Total equals sale proceeds minus acquisition cost")
    func totalEqualsProceedsMinusAcquisitionCost() throws {
        let run = try makeRun(targetPrice: 90, targetDay: 20)
        let acquisitionCost = Decimal(1000) * Decimal(150) + Decimal(1000) * Decimal(90)
        let proceeds = Decimal(1000) * Decimal(130)

        #expect(run.remainingQuantity == 1000)
        #expect(run.remainingMarketValue + proceeds == acquisitionCost + run.totalBeforeSaleCosts)
        #expect(run.totalBeforeSaleCosts == 20000)
    }

    @Test("Conservation holds with fees on the lots")
    func conservationHoldsWithFees() throws {
        let run = try makeRun(targetPrice: 90, targetDay: 20, fees: 1425)
        let acquisitionCost = Decimal(1000) * Decimal(150) + Decimal(1000) * Decimal(90) + Decimal(1425) * 2

        #expect(run.remainingMarketValue + Decimal(1000) * Decimal(130) == acquisitionCost + run.totalBeforeSaleCosts)
        #expect(run.totalBeforeSaleCosts == Decimal(20000) - Decimal(1425) * 2)
    }

    @Test("Conservation holds for a split sale across both lots")
    func conservationHoldsForSplitSale() throws {
        let store = try setUp()
        let context = store.context
        let dear = addBuyLot(context, day: 10, price: 150)
        let cheap = addBuyLot(context, day: 20, price: 90)

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
        let holding = HoldingCalculator.currentHoldings(from: [dear, cheap])[0]
        let unrealized = Decimal(130) * Decimal(holding.totalQuantity) - holding.totalRemainingCost

        let proceeds = Decimal(1000) * Decimal(130)
        let acquisitionCost = Decimal(1000) * Decimal(150) + Decimal(1000) * Decimal(90)

        #expect(holding.totalQuantity == 1000)
        #expect(result.realizedResult == Decimal(4000) - result.totalDeductions)
        #expect(
            result.realizedResult + result.totalDeductions + unrealized
                == holding.totalRemainingCost + unrealized + proceeds - acquisitionCost
        )
        #expect(result.realizedResult + result.totalDeductions + unrealized == 20000)
    }

    @Test("Conservation holds after repeated sales of the same symbol")
    func conservationHoldsAfterRepeatedSales() throws {
        let store = try setUp()
        let context = store.context
        let dear = addBuyLot(context, day: 10, price: 150)
        let cheap = addBuyLot(context, day: 20, price: 90)

        func sell(lot: Lot, price: Decimal, day: Int, quantity: Int) throws {
            let sale = try SaleStore.save(
                symbol: "2330",
                saleDate: Fixtures.makeDate(2026, 3, day),
                quantity: quantity,
                pricePerShare: price,
                drafts: [DraftAllocation(lot: lot, quantity: quantity)],
                rates: rates,
                in: context
            )
            _ = RealizedPnLCalculator.result(
                for: sale,
                allocations: try SaleStore.allocations(for: sale, in: context)
            )
        }

        try sell(lot: dear, price: 160, day: 3, quantity: 500)
        try sell(lot: cheap, price: 130, day: 5, quantity: 500)

        let holding = HoldingCalculator.currentHoldings(from: [dear, cheap])[0]
        let unrealized = Decimal(130) * Decimal(holding.totalQuantity) - holding.totalRemainingCost
        let proceeds = Decimal(500) * Decimal(160) + Decimal(500) * Decimal(130)
        let acquisitionCost = Decimal(1000) * Decimal(150) + Decimal(1000) * Decimal(90)
        let realized = (try context.fetch(FetchDescriptor<Sale>()))
            .compactMap { sale in
                try? RealizedPnLCalculator.result(
                    for: sale,
                    allocations: SaleStore.allocations(for: sale, in: context)
                ).realizedResult
            }
            .reduce(Decimal.zero, +)

        #expect(holding.totalQuantity == 1000)
        #expect(
            realized + saleDeductionsTotal(context) + unrealized
                == holding.totalRemainingCost + unrealized + proceeds - acquisitionCost
        )
        #expect(realized + saleDeductionsTotal(context) + unrealized == 35000)
    }
}