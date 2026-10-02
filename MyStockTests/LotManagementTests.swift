import Foundation
import Testing
import SwiftData
@testable import MyStock

@Suite("Lot create, edit and delete")
struct LotManagementTests {
    @Test("Deleting a lot that has sale allocations")
    func deletingALotWithAllocations() throws {
        let container = try Persistence.makeInMemoryContainer()
        let context = ModelContext(container)

        let lotAt90 = Lot(
            symbol: "2330",
            lotDate: Fixtures.makeDate(2026, 2, 20),
            quantity: 1000,
            pricePerShare: 90
        )
        let lotAt150 = Lot(
            symbol: "2330",
            lotDate: Fixtures.makeDate(2026, 1, 10),
            quantity: 1000,
            pricePerShare: 150
        )
        let sale = Sale(
            symbol: "2330",
            saleDate: Fixtures.makeDate(2026, 3, 5),
            quantity: 1000,
            pricePerShare: 130
        )
        context.insert(lotAt90)
        context.insert(lotAt150)
        context.insert(sale)
        context.insert(SaleAllocation(sale: sale, lot: lotAt90, quantity: 1000))
        try context.save()

        try LotStore.delete(lotAt90, in: context)

        let remainingLots = try context.fetch(FetchDescriptor<Lot>())
        #expect(remainingLots.count == 1)
        #expect(remainingLots.first?.remainingQuantity == 1000)
        #expect(remainingLots.first?.totalCost == 150000)

        let allocations = try context.fetch(FetchDescriptor<SaleAllocation>())
        #expect(allocations.count == 0)
        #expect(sale.quantity == 1000)
    }

    @Test("Deleting a lot restores the aggregate to the surviving lots")
    func aggregateAfterDelete() throws {
        let container = try Persistence.makeInMemoryContainer()
        let context = ModelContext(container)

        let lotAt90 = Lot(symbol: "2330", lotDate: Fixtures.makeDate(2026, 2, 20), quantity: 1000, pricePerShare: 90)
        let lotAt150 = Lot(symbol: "2330", lotDate: Fixtures.makeDate(2026, 1, 10), quantity: 1000, pricePerShare: 150)
        let allocation = Lot(symbol: "2330", lotDate: Fixtures.makeDate(2026, 3, 5), quantity: 1000, pricePerShare: 130)
        _ = allocation
        context.insert(lotAt90)
        context.insert(lotAt150)
        try context.save()

        try LotStore.delete(lotAt90, in: context)

        let lots = try context.fetch(FetchDescriptor<Lot>())
        let totalQuantity = lots.reduce(0) { $0 + $1.remainingQuantity }
        let totalCost = lots.reduce(Decimal.zero) { $0 + $1.remainingCost }
        #expect(totalQuantity == 1000)
        #expect(totalCost == 150000)
    }

    @Test("Editing a lot keeps the sold quantity deducted")
    func editKeepsSoldQuantityDeducted() throws {
        let container = try Persistence.makeInMemoryContainer()
        let context = ModelContext(container)

        let lot = Lot(symbol: "2330", lotDate: Fixtures.makeDate(2026, 1, 10), quantity: 1000, pricePerShare: 150)
        context.insert(lot)
        try context.save()

        let sale = Sale(symbol: "2330", saleDate: Fixtures.makeDate(2026, 3, 5), quantity: 300, pricePerShare: 130)
        context.insert(sale)
        context.insert(SaleAllocation(sale: sale, lot: lot, quantity: 300))
        lot.remainingQuantity = 700
        try context.save()

        try LotStore.update(
            lot,
            symbol: "2330",
            lotDate: Fixtures.makeDate(2026, 1, 10),
            quantity: 2000,
            pricePerShare: 120,
            lotType: .buy,
            in: context
        )

        #expect(lot.quantity == 2000)
        #expect(lot.remainingQuantity == 1700)
        #expect(lot.pricePerShare == 120)
    }
}
