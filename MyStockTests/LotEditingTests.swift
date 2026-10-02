import Foundation
import SwiftData
import Testing
@testable import MyStock

@MainActor
@Suite("Lot editing and deletion")
struct LotEditingTests {
    private func makeContext() throws -> ModelContext {
        try ModelContext(Persistence.makeInMemoryContainer())
    }

    private var rates: FeeRates {
        FeeRates(
            commissionRate: Decimal(string: "0.001425") ?? .zero,
            transactionTaxRate: Decimal(string: "0.003") ?? .zero
        )
    }

    private func buyLot(
        in context: ModelContext,
        symbol: String = "2330",
        day: Int = 10,
        quantity: Int = 1000,
        price: Decimal = 150,
        fees: Decimal = 0
    ) -> Lot {
        let lot = Lot(
            symbol: symbol,
            lotDate: Fixtures.makeDate(2026, 1, day),
            quantity: quantity,
            pricePerShare: price,
            totalFees: fees
        )
        context.insert(lot)
        return lot
    }

    private func sell(
        in context: ModelContext,
        quantity: Int,
        price: Decimal = 130,
        drafts: [DraftAllocation]
    ) throws -> Sale {
        try SaleStore.save(
            symbol: "2330",
            saleDate: Fixtures.makeDate(2026, 3, 5),
            quantity: quantity,
            pricePerShare: price,
            drafts: drafts,
            rates: rates,
            in: context
        )
    }

    @Test("Editing a lot changes its recorded figures")
    func editingChangesFigures() throws {
        let context = try makeContext()
        let lot = buyLot(in: context, quantity: 1000, price: 150, fees: 213)
        let feesBefore = lot.feeBreakdown

        try LotStore.update(
            lot,
            symbol: "2330",
            lotDate: Fixtures.makeDate(2026, 2, 1),
            quantity: 1500,
            pricePerShare: 120,
            lotType: .buy,
            in: context
        )

        #expect(lot.symbol == "2330")
        #expect(lot.lotDate == Fixtures.makeDate(2026, 2, 1))
        #expect(lot.quantity == 1500)
        #expect(lot.pricePerShare == 120)
        #expect(lot.remainingQuantity == 1500)
        #expect(lot.feeBreakdown == feesBefore, "編輯不得更動建立當時記錄的費用")
    }

    @Test("Editing keeps the shares already sold out of the remaining count")
    func editingKeepsSoldQuantity() throws {
        let context = try makeContext()
        let lot = buyLot(in: context, quantity: 1000)
        _ = try sell(in: context, quantity: 400, drafts: [DraftAllocation(lot: lot, quantity: 400)])

        try LotStore.update(
            lot,
            symbol: "2330",
            lotDate: lot.lotDate,
            quantity: 800,
            pricePerShare: 150,
            lotType: .buy,
            in: context
        )

        #expect(lot.quantity == 800)
        #expect(lot.remainingQuantity == 400, "已賣出的 400 股不應回到剩餘股數")
    }

    @Test("Editing does not recalculate the fees that were snapshotted at creation")
    func editingKeepsSnapshottedFees() throws {
        let context = try makeContext()
        let lot = buyLot(in: context, quantity: 1000, price: 150, fees: 1425)

        try LotStore.update(
            lot,
            symbol: "2330",
            lotDate: lot.lotDate,
            quantity: 5000,
            pricePerShare: 400,
            lotType: .buy,
            in: context
        )

        #expect(lot.totalFees == 1425, "費率於建立當時固定，之後修改不應回溯")
    }

    @Test("Deleting a lot removes it and the allocations that referenced it")
    func deletingRemovesAllocations() throws {
        let context = try makeContext()
        let dear = buyLot(in: context, day: 10, price: 150)
        let cheap = buyLot(in: context, day: 20, price: 90)
        let sale = try sell(in: context, quantity: 1000, drafts: [DraftAllocation(lot: cheap, quantity: 1000)])

        try LotStore.delete(cheap, in: context)

        #expect(try context.fetch(FetchDescriptor<Lot>()).map(\.id) == [dear.id])
        #expect(try context.fetch(FetchDescriptor<SaleAllocation>()).isEmpty)
        #expect(try SaleStore.allocations(for: sale, in: context).isEmpty)
    }

    @Test("Deleting a lot recomputes the holding")
    func deletingRecomputesHolding() throws {
        let context = try makeContext()
        _ = buyLot(in: context, day: 10, price: 150)
        let cheap = buyLot(in: context, day: 20, price: 90)
        _ = try sell(in: context, quantity: 1000, drafts: [DraftAllocation(lot: cheap, quantity: 1000)])

        try LotStore.delete(cheap, in: context)

        let remaining = try context.fetch(FetchDescriptor<Lot>())
        let holding = HoldingCalculator.currentHoldings(from: remaining)[0]
        #expect(holding.totalQuantity == 1000)
        #expect(holding.totalRemainingCost == 150000)
    }

    @Test("Deleting a lot that was never sold leaves other lots alone")
    func deletingUnsoldLot() throws {
        let context = try makeContext()
        let dear = buyLot(in: context, day: 10, price: 150)
        let cheap = buyLot(in: context, day: 20, price: 90)

        try LotStore.delete(cheap, in: context)

        #expect(try context.fetch(FetchDescriptor<Lot>()).map(\.id) == [dear.id])
        #expect(try context.fetch(FetchDescriptor<SaleAllocation>()).isEmpty)
    }

    @Test("Shrinking a lot below what was already sold is rejected")
    func shrinkingBelowSoldQuantityIsRejected() throws {
        let context = try makeContext()
        let lot = buyLot(in: context, quantity: 1000)
        _ = try sell(in: context, quantity: 600, drafts: [DraftAllocation(lot: lot, quantity: 600)])

        var caught: LotEditError?
        do {
            try LotStore.update(
                lot,
                symbol: "2330",
                lotDate: lot.lotDate,
                quantity: 300,
                pricePerShare: 150,
                lotType: .buy,
                in: context
            )
        } catch let error as LotEditError {
            caught = error
        }

        #expect(caught == .quantityBelowSoldQuantity(quantity: 300, soldQuantity: 600))
        #expect(lot.quantity == 1000, "被拒絕的修改不應寫入")
        #expect(lot.remainingQuantity == 400)
    }

    @Test("Shrinking a lot to exactly what was already sold is allowed")
    func shrinkingToSoldQuantityIsAllowed() throws {
        let context = try makeContext()
        let lot = buyLot(in: context, quantity: 1000)
        _ = try sell(in: context, quantity: 600, drafts: [DraftAllocation(lot: lot, quantity: 600)])

        try LotStore.update(
            lot,
            symbol: "2330",
            lotDate: lot.lotDate,
            quantity: 600,
            pricePerShare: 150,
            lotType: .buy,
            in: context
        )

        #expect(lot.quantity == 600)
        #expect(lot.remainingQuantity == 0)
    }

    @Test("A sale left with no allocations is reported as incompletely allocated")
    func deletingReportsIncompleteAllocation() throws {
        let context = try makeContext()
        _ = buyLot(in: context, day: 10, price: 150)
        let cheap = buyLot(in: context, day: 20, price: 90)
        let sale = try sell(in: context, quantity: 1000, drafts: [DraftAllocation(lot: cheap, quantity: 1000)])

        let before = RealizedPnLCalculator.result(
            for: sale,
            allocations: try SaleStore.allocations(for: sale, in: context)
        )
        #expect(before.isCompleteAllocation)

        try LotStore.delete(cheap, in: context)

        let after = RealizedPnLCalculator.result(
            for: sale,
            allocations: try SaleStore.allocations(for: sale, in: context)
        )
        #expect(after.allocatedQuantity == 0)
        #expect(after.isCompleteAllocation == false)
        #expect(after.realizedResult == 0)
    }

    @Test("Allocations and sold quantity can be looked up per lot")
    func allocationsForLot() throws {
        let context = try makeContext()
        let dear = buyLot(in: context, day: 10, price: 150)
        let cheap = buyLot(in: context, day: 20, price: 90)
        _ = try sell(in: context, quantity: 500, drafts: [DraftAllocation(lot: cheap, quantity: 500)])

        #expect(try LotStore.allocations(for: dear, in: context).isEmpty)
        #expect(try LotStore.allocations(for: cheap, in: context).count == 1)
        #expect(LotStore.soldQuantity(of: cheap) == 500)
        #expect(LotStore.soldQuantity(of: dear) == 0)
    }

    @Test("A stock allocation lot keeps zero costs when edited")
    func editingStockAllocation() throws {
        let context = try makeContext()
        let lot = Lot(
            symbol: "2330",
            lotDate: Fixtures.makeDate(2026, 4, 1),
            quantity: 200,
            pricePerShare: 0,
            totalFees: 0,
            lotType: .stockAllocation
        )
        context.insert(lot)

        try LotStore.update(
            lot,
            symbol: "2330",
            lotDate: Fixtures.makeDate(2026, 4, 2),
            quantity: 300,
            pricePerShare: 0,
            lotType: .stockAllocation,
            in: context
        )

        #expect(lot.quantity == 300)
        #expect(lot.pricePerShare == 0)
        #expect(lot.totalFees == 0)
        #expect(lot.remainingQuantity == 300)
        #expect(lot.lotType == .stockAllocation)
    }
}