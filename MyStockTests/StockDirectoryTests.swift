import Foundation
import Testing
import SwiftData
@testable import MyStock

@Suite("Stock name lookup")
struct StockDirectoryTests {
    private func makeContainer() throws -> ModelContainer {
        try Persistence.makeInMemoryContainer()
    }

    @Test("A TWSE title yields the Chinese short name")
    func parsesTWSETitle() throws {
        let name = StockDirectory.parseTWSETitle(
            "115年06月 2330 台積電           各日成交資訊",
            symbol: "2330"
        )
        #expect(name == "台積電")
    }

    @Test("A TWSE title with a multi character company name is kept whole")
    func parsesLongCompanyName() throws {
        let name = StockDirectory.parseTWSETitle(
            "115年06月 2330 台灣積體電路製造           各日成交資訊",
            symbol: "2330"
        )
        #expect(name == "台灣積體電路製造")
    }

    @Test("A title without the symbol yields no name")
    func rejectsTitleWithoutSymbol() {
        #expect(StockDirectory.parseTWSETitle("查無資料", symbol: "9999") == nil)
    }

    @Test("The TWSE short name is preferred over an English name")
    func prefersTWSE() async throws {
        let client = FakeHTTPClient()
        await client.stub(host: "www.twse.com.tw", result: .success(Data("""
        {"stat":"OK","title":"115年06月 2330 台積電           各日成交資訊","fields":[],"data":[]}
        """.utf8)))
        let directory = StockDirectory(client: client)

        let resolved = await directory.name(for: "2330")
        #expect(resolved.name == "台積電")
        #expect(resolved.source == .twse)
    }

    @Test("An unlisted TWSE code falls through to TPEx")
    func fallsBackToTPEx() async throws {
        let client = FakeHTTPClient()
        await client.stub(host: "www.twse.com.tw", result: .success(Data("""
        {"stat":"很抱歉，沒有符合條件的資料!","fields":[],"data":[]}
        """.utf8)))
        await client.stub(host: "www.tpex.org.tw", result: .success(Data("""
        {"tables":[{"fields":["代號","名稱","收盤 "],"data":[["6488","環球晶","420.0"]]}]}
        """.utf8)))
        let directory = StockDirectory(client: client)

        let resolved = await directory.name(for: "6488")
        #expect(resolved.name == "環球晶")
        #expect(resolved.source == .tpex)
    }

    @Test("Yahoo is the last resort and gives an English name")
    func fallsBackToYahoo() async throws {
        let client = FakeHTTPClient()
        await client.stub(host: "www.twse.com.tw", result: .success(Data("""
        {"stat":"很抱歉，沒有符合條件的資料!","fields":[],"data":[]}
        """.utf8)))
        await client.stub(host: "www.tpex.org.tw", result: .success(Data("""
        {"tables":[{"fields":["代號","名稱","收盤 "],"data":[]}]}
        """.utf8)))
        await client.stub(host: "query1.finance.yahoo.com", result: .success(Data("""
        {"chart":{"result":[{"meta":{"shortName":"TAIWAN SEMICONDUCTOR"}}],"error":null}}
        """.utf8)))
        let directory = StockDirectory(client: client)

        let resolved = await directory.name(for: "2330")
        #expect(resolved.name == "TAIWAN SEMICONDUCTOR")
        #expect(resolved.source == .yahoo)
    }

    @Test("An unknown symbol resolves to no name instead of failing hard")
    func unknownSymbolHasNoName() async throws {
        let directory = StockDirectory(client: FakeHTTPClient())
        let resolved = await directory.name(for: "9999")
        #expect(resolved.name == nil)
    }

    @Test("A resolved name is answered from cache on the second ask")
    func cachesResolvedName() async throws {
        let client = FakeHTTPClient()
        await client.stub(host: "www.twse.com.tw", result: .success(Data("""
        {"stat":"OK","title":"115年06月 2330 台積電           各日成交資訊","fields":[],"data":[]}
        """.utf8)))
        let directory = StockDirectory(client: client)

        _ = await directory.name(for: "2330")
        let second = await directory.name(for: "2330")
        #expect(second.source == .cache)
        #expect(second.name == "台積電")
        let count = await client.requestCount()
        #expect(count == 1)
    }

    @Test("A name on file is reused without a network lookup")
    func storedNameSkipsLookup() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        try StockStore.upsertName("台積電", for: "2330", in: context)

        #expect(StockStore.name(for: "2330", in: context) == "台積電")
        #expect(StockStore.name(for: "2317", in: context) == nil)
    }

    @Test("Saving a corrected name updates the existing row rather than adding one")
    func upsertKeepsOneRowPerSymbol() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        try StockStore.upsertName("台積", for: "2330", in: context)
        try StockStore.upsertName("台積電", for: "2330", in: context)

        let stocks = try context.fetch(FetchDescriptor<Stock>())
        #expect(stocks.count == 1)
        #expect(stocks.first?.name == "台積電")
    }

    @Test("Holding metrics carry the stored name")
    func metricsCarryDisplayName() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        try StockStore.upsertName("台積電", for: "2330", in: context)

        let lot = Lot(symbol: "2330", lotDate: Fixtures.makeDate(2026, 1, 10), quantity: 1000, pricePerShare: 150)
        context.insert(lot)
        try context.save()

        let holdings = HoldingCalculator.currentHoldings(from: [lot])
        var named = holdings
        named[0].displayName = StockStore.name(for: "2330", in: context)

        let metrics = UnrealizedPnLCalculator.metrics(
            for: named[0],
            quote: Quote(symbol: "2330", currentPrice: 180, previousClose: 175, source: .yahooFinance, isFallback: false)
        )
        #expect(metrics.displayName == "台積電")
        #expect(metrics.symbol == "2330")
    }
}