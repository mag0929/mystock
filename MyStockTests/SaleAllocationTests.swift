import Foundation
import SwiftData
import Testing
@testable import MyStock

@MainActor
@Suite("Sale allocation input and integrity")
struct SaleAllocationTests {
    private struct Store {
        let container: ModelContainer
        let context: ModelContext
    }

    private func setUp() throws -> Store {
        let container = try Persistence.makeInMemoryContainer()
        return Store(container: container, context: ModelContext(container))
    }

    private func makeLot(
        in context: ModelContext,
        day: Int,
        price: Decimal,
        quantity: Int = 1000,
        type: LotType = .buy
    ) -> Lot {
        let lot = Lot(
            symbol: "2330",
            lotDate: Fixtures.makeDate(2026, 2, day),
            quantity: quantity,
            pricePerShare: price,
            lotType: type
        )
        context.insert(lot)
        return lot
    }

    private var rates: FeeRates {
        FeeRates(commissionRate: Decimal(string: "0.001425") ?? .zero, transactionTaxRate: Decimal(string: "0.003") ?? .zero)
    }

    @Test("Allocating a sale to a single lot")
    func allocatingToASingleLot() throws {
        let store = try setUp()
        let context = store.context
        let lot = makeLot(in: context, day: 20, price: 90)
        let other = makeLot(in: context, day: 10, price: 150)
        try context.save()

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
        #expect(allocations.count == 1)
        #expect(allocations.first?.quantity == 1000)
        #expect(allocations.first?.lot?.id == lot.id)
        #expect(other.remainingQuantity == 1000)
        #expect(lot.remainingQuantity == 0)
    }

    @Test("Allocating a sale across multiple lots")
    func allocatingAcrossMultipleLots() throws {
        let store = try setUp()
        let context = store.context
        let cheap = makeLot(in: context, day: 20, price: 90)
        let dear = makeLot(in: context, day: 10, price: 150)
        try context.save()

        let sale = try SaleStore.save(
            symbol: "2330",
            saleDate: Fixtures.makeDate(2026, 3, 5),
            quantity: 1000,
            pricePerShare: 130,
            drafts: [DraftAllocation(lot: cheap, quantity: 400), DraftAllocation(lot: dear, quantity: 600)],
            rates: rates,
            in: context
        )

        let allocations = try SaleStore.allocations(for: sale, in: context)
        #expect(allocations.count == 2)
        #expect(allocations.map(\.quantity).reduce(0, +) == 1000)
        #expect(cheap.remainingQuantity == 600)
        #expect(dear.remainingQuantity == 400)
    }

    @Test("Unallocated shares are rejected")
    func unallocatedSharesAreRejected() throws {
        let store = try setUp()
        let context = store.context
        let lot = makeLot(in: context, day: 20, price: 90)
        try context.save()

        var caught: AllocationValidationError?
        do {
            _ = try SaleStore.save(
                symbol: "2330",
                saleDate: Fixtures.makeDate(2026, 3, 5),
                quantity: 1000,
                pricePerShare: 130,
                drafts: [DraftAllocation(lot: lot, quantity: 900)],
                rates: rates,
                in: context
            )
        } catch let error as AllocationValidationError {
            caught = error
        }

        #expect(caught == .unallocatedSharesRemaining(100))
        #expect(caught.map { AllocationValidator.message(for: $0) } == "尚有 100 股未分配")
        #expect(lot.remainingQuantity == 1000)
    }

    @Test("Allocated quantity mismatch")
    func allocatedQuantityMismatch() throws {
        let store = try setUp()
        let context = store.context
        let lot = makeLot(in: context, day: 20, price: 90, quantity: 2000)
        try context.save()

        var caught: AllocationValidationError?
        do {
            _ = try SaleStore.save(
                symbol: "2330",
                saleDate: Fixtures.makeDate(2026, 3, 5),
                quantity: 1000,
                pricePerShare: 130,
                drafts: [DraftAllocation(lot: lot, quantity: 1100)],
                rates: rates,
                in: context
            )
        } catch let error as AllocationValidationError {
            caught = error
        }

        #expect(caught == .allocationExceedsSaleQuantity(by: 100))
        #expect(lot.remainingQuantity == 2000)
    }

    @Test("Allocation exceeds a lot's remaining shares")
    func allocationExceedsLotRemainingShares() throws {
        let store = try setUp()
        let context = store.context
        let lot = makeLot(in: context, day: 20, price: 90)
        lot.remainingQuantity = 500
        try context.save()

        var caught: AllocationValidationError?
        do {
            _ = try SaleStore.save(
                symbol: "2330",
                saleDate: Fixtures.makeDate(2026, 3, 5),
                quantity: 600,
                pricePerShare: 130,
                drafts: [DraftAllocation(lot: lot, quantity: 600)],
                rates: rates,
                in: context
            )
        } catch let error as AllocationValidationError {
            caught = error
        }

        #expect(caught == .lotHasInsufficientShares(lotDate: lot.lotDate, available: 500, requested: 600))
        #expect(AllocationValidator.message(for: caught!).contains("僅剩 500 股"))
        #expect(lot.remainingQuantity == 500)
    }

    @Test("Duplicate allocation to the same lot")
    func duplicateAllocationToTheSameLot() throws {
        let store = try setUp()
        let context = store.context
        let lot = makeLot(in: context, day: 20, price: 90)
        lot.remainingQuantity = 500
        try context.save()

        var caught: AllocationValidationError?
        do {
            _ = try SaleStore.save(
                symbol: "2330",
                saleDate: Fixtures.makeDate(2026, 3, 5),
                quantity: 700,
                pricePerShare: 130,
                drafts: [DraftAllocation(lot: lot, quantity: 400), DraftAllocation(lot: lot, quantity: 300)],
                rates: rates,
                in: context
            )
        } catch let error as AllocationValidationError {
            caught = error
        }

        #expect(caught == .lotHasInsufficientShares(lotDate: lot.lotDate, available: 500, requested: 700))
        #expect(lot.remainingQuantity == 500)
    }

    @Test("Stock allocation lots are rejected")
    func stockAllocationLotsAreRejected() throws {
        let store = try setUp()
        let context = store.context
        let allocation = makeLot(in: context, day: 1, price: 0, quantity: 200, type: .stockAllocation)
        try context.save()

        var caught: AllocationValidationError?
        do {
            _ = try SaleStore.save(
                symbol: "2330",
                saleDate: Fixtures.makeDate(2026, 3, 5),
                quantity: 200,
                pricePerShare: 130,
                drafts: [DraftAllocation(lot: allocation, quantity: 200)],
                rates: rates,
                in: context
            )
        } catch let error as AllocationValidationError {
            caught = error
        }

        #expect(caught == .stockAllocationLotNotAllowed(lotDate: allocation.lotDate))
        #expect(AllocationValidator.message(for: caught!).contains("配股批次"))
    }

    @Test("A sale without any allocation is rejected")
    func saleWithoutAllocationIsRejected() throws {
        let store = try setUp()
        let context = store.context
        var caught: AllocationValidationError?
        do {
            _ = try SaleStore.save(
                symbol: "2330",
                saleDate: Fixtures.makeDate(2026, 3, 5),
                quantity: 1000,
                pricePerShare: 130,
                drafts: [],
                rates: rates,
                in: context
            )
        } catch let error as AllocationValidationError {
            caught = error
        }

        #expect(caught == .unallocatedSharesRemaining(1000))
    }

    @Test("A lot from another symbol is rejected")
    func lotFromAnotherSymbolIsRejected() throws {
        let store = try setUp()
        let context = store.context
        let foreign = Lot(symbol: "2317", lotDate: Fixtures.makeDate(2026, 2, 20), quantity: 1000, pricePerShare: 90)
        context.insert(foreign)
        try context.save()

        var caught: AllocationValidationError?
        do {
            _ = try SaleStore.save(
                symbol: "2330",
                saleDate: Fixtures.makeDate(2026, 3, 5),
                quantity: 1000,
                pricePerShare: 130,
                drafts: [DraftAllocation(lot: foreign, quantity: 1000)],
                rates: rates,
                in: context
            )
        } catch let error as AllocationValidationError {
            caught = error
        }

        #expect(caught == .symbolMismatch)
    }
}