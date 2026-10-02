import Foundation
import Testing
import SwiftData
@testable import MyStock

@Suite("Local-only persistence")
struct LocalOnlyPersistenceTests {
    @Test("Relaunching the app")
    func relaunchingTheApp() throws {
        let container = try Persistence.makeInMemoryContainer()
        let context = ModelContext(container)

        let lot = Lot(
            symbol: "2330",
            lotDate: Fixtures.makeDate(2026, 1, 10),
            quantity: 2000,
            pricePerShare: 150,
            totalFees: 0
        )
        lot.remainingQuantity = 1500
        context.insert(lot)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Lot>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.remainingQuantity == 1500)
        #expect(fetched.first?.totalCost == 300000)
    }

    @Test("Lots survive a fresh container without any network access")
    func lotsSurviveFreshContainer() throws {
        let schema = Schema([Lot.self, Sale.self, SaleAllocation.self, Stock.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let lot = Lot(
            symbol: "2330",
            lotDate: Fixtures.makeDate(2026, 1, 10),
            quantity: 2000,
            pricePerShare: 150
        )
        lot.remainingQuantity = 1500
        context.insert(lot)
        try context.save()

        let reopened = try ModelContext(container)
        let fetched = try reopened.fetch(FetchDescriptor<Lot>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.symbol == "2330")
    }

    @Test("A stock allocation lot persists with zero cost")
    func stockAllocationPersists() throws {
        let container = try Persistence.makeInMemoryContainer()
        let context = ModelContext(container)

        context.insert(
            Lot(
                symbol: "2330",
                lotDate: Fixtures.makeDate(2026, 4, 1),
                quantity: 200,
                pricePerShare: 0,
                lotType: .stockAllocation
            )
        )
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Lot>())
        #expect(fetched.first?.lotType == .stockAllocation)
        #expect(fetched.first?.totalCost == 0)
        #expect(fetched.first?.remainingQuantity == 200)
    }
}
