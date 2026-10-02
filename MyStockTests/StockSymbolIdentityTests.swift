import Foundation
import Testing
import SwiftData
@testable import MyStock

@Suite("Stock symbol identity")
struct StockSymbolIdentityTests {
    private func makeContainer() throws -> ModelContainer {
        try Persistence.makeInMemoryContainer()
    }

    @Test("Lots of the same symbol group under one holding entry")
    func lotsGroupUnderOneEntry() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        context.insert(
            Lot(symbol: "2330", lotDate: Fixtures.makeDate(2026, 1, 10), quantity: 1000, pricePerShare: 150)
        )
        context.insert(
            Lot(symbol: "2330", lotDate: Fixtures.makeDate(2026, 2, 20), quantity: 1000, pricePerShare: 90)
        )
        try context.save()

        let symbols = Set(try context.fetch(FetchDescriptor<Lot>()).map(\.symbol))
        #expect(symbols == ["2330"])
        #expect(try context.fetch(FetchDescriptor<Lot>()).count == 2)
    }

    @Test("A stock name can be supplied once and reused for later lots")
    func nameReusedForLaterLots() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        context.insert(Stock(symbol: "2330", name: "台積電"))
        try context.save()

        let existing = try context.fetch(FetchDescriptor<Stock>())
        #expect(existing.count == 1)
        #expect(existing.first?.name == "台積電")
        #expect(existing.first?.symbol == "2330")
    }

    @Test("A stock name can be corrected at any time")
    func nameCanBeCorrected() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let stock = Stock(symbol: "2330", name: "台積")
        context.insert(stock)
        try context.save()

        stock.name = "台積電"
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Stock>())
        #expect(fetched.first?.name == "台積電")
    }
}
