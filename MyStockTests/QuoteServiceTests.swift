import Foundation
import Testing
@testable import MyStock

actor FakeHTTPClient: HTTPClient {
    var responders: [String: Result<Data, Error>] = [:]
    private(set) var requestedURLs: [URL] = []

    func stub(host: String, result: Result<Data, Error>) {
        responders[host] = result
    }

    func requestCount() -> Int {
        requestedURLs.count
    }

    func reset() {
        requestedURLs.removeAll()
    }

    func data(from url: URL, headers: [String: String]) async throws -> Data {
        requestedURLs.append(url)
        guard let host = url.host, let responder = responders[host] else {
            throw QuoteError.noUsablePrice(symbol: url.absoluteString)
        }
        return try responder.get()
    }
}

struct StubResponse {
    static let yahooSuccess = """
    {"chart":{"result":[{"meta":{"regularMarketPrice":130.0,"chartPreviousClose":125.0}}],"error":null}}
    """

    static let yahooErrorPayload = """
    {"chart":{"result":null,"error":{"code":"Not Found"}}}
    """

    static let yahooNoPrice = """
    {"chart":{"result":[{"meta":{"currency":"TWD","symbol":"9999.TW"}}],"error":null}}
    """

    static func twseClose(_ price: String) -> String {
        """
        {"stat":"OK","date":"20260901","fields":["日期","成交股數","成交金額","開盤價","最高價","最低價","收盤價","漲跌價差","成交筆數","註記"],
        "data":[["115/09/29","1,000","1,000,000","127.00","128.00","126.00","\(price)","+1.00","10",""],
                ["115/09/30","1,000","1,000,000","128.00","\(price)","\(price)","\(price)","+2.00","10",""]]}
        """
    }

    static func tpexClose(symbol: String, price: String) -> String {
        """
        {"tables":[{"title":"上櫃股票每日收盤行情","fields":["代號","名稱","收盤 ","漲跌","開盤 ","最高 ","最低"],
        "data":[["2317","鴻海","\(price)","+0.23","10.55","10.61","10.50"],["\(symbol)","測試","\(price)","+0.10","10.00","10.20","9.90"]]}]}
        """
    }
}

enum StubError: Error {
    case offline
}

@Suite("Quote retrieval")
struct QuoteServiceTests {
    private func makeClient() -> FakeHTTPClient {
        FakeHTTPClient()
    }

    @Test("Primary source succeeds")
    func primarySourceSucceeds() async {
        let client = makeClient()
        await client.stub(host: "query1.finance.yahoo.com", result: .success(Data(StubResponse.yahooSuccess.utf8)))

        let quote = await QuoteService(client: client).quote(for: "2330")

        #expect(quote.currentPrice == 130)
        #expect(quote.previousClose == 125)
        #expect(quote.source == .yahooFinance)
        #expect(quote.isFallback == false)
        #expect(quote.changePercentage == Decimal(string: "0.04"))
    }

    @Test("Primary source fails and TWSE fallback is used")
    func primarySourceFails() async {
        let client = makeClient()
        await client.stub(host: "query1.finance.yahoo.com", result: .failure(StubError.offline))
        await client.stub(host: "www.twse.com.tw", result: .success(Data(StubResponse.twseClose("128.00").utf8)))

        let quote = await QuoteService(client: client).quote(for: "2330")

        #expect(quote.currentPrice == 128)
        #expect(quote.previousClose == 128)
        #expect(quote.source == .twse)
        #expect(quote.isFallback == true)
        #expect(quote.changePercentage == 0)
    }

    @Test("Primary returns no usable price and TPEx fallback is used")
    func primaryReturnsNoPriceThenTPEx() async {
        let client = makeClient()
        await client.stub(host: "query1.finance.yahoo.com", result: .success(Data(StubResponse.yahooNoPrice.utf8)))
        await client.stub(host: "www.twse.com.tw", result: .failure(StubError.offline))
        await client.stub(host: "www.tpex.org.tw", result: .success(Data(StubResponse.tpexClose(symbol: "6488", price: "72.5").utf8)))

        let quote = await QuoteService(client: client).quote(for: "6488")

        #expect(quote.currentPrice == Decimal(string: "72.5"))
        #expect(quote.previousClose == Decimal(string: "72.5"))
        #expect(quote.source == .tpex)
        #expect(quote.isFallback == true)
    }

    @Test("Yahoo error payload is treated as a failure")
    func yahooErrorPayloadTreatedAsFailure() async {
        let client = makeClient()
        await client.stub(host: "query1.finance.yahoo.com", result: .success(Data(StubResponse.yahooErrorPayload.utf8)))
        await client.stub(host: "www.twse.com.tw", result: .success(Data(StubResponse.twseClose("128.00").utf8)))

        let quote = await QuoteService(client: client).quote(for: "2330")

        #expect(quote.isFallback == true)
        #expect(quote.source == .twse)
    }

    @Test("Both sources fail")
    func bothSourcesFail() async {
        let client = makeClient()
        await client.stub(host: "query1.finance.yahoo.com", result: .failure(StubError.offline))
        await client.stub(host: "www.twse.com.tw", result: .failure(StubError.offline))
        await client.stub(host: "www.tpex.org.tw", result: .failure(StubError.offline))

        let quote = await QuoteService(client: client).quote(for: "2330")

        #expect(quote.currentPrice == nil)
        #expect(quote.previousClose == nil)
        #expect(quote.source == nil)
        #expect(quote.isAvailable == false)
    }

    @Test("A quote is fetched once per symbol until the cache is cleared")
    func quotesAreCached() async {
        let client = makeClient()
        await client.stub(host: "query1.finance.yahoo.com", result: .success(Data(StubResponse.yahooSuccess.utf8)))
        let service = QuoteService(client: client)

        _ = await service.quote(for: "2330")
        _ = await service.quote(for: "2330")
        let countBeforeClear = await client.requestCount()

        await service.clearCache()
        _ = await service.quote(for: "2330")
        let countAfterClear = await client.requestCount()

        #expect(countBeforeClear == 1)
        #expect(countAfterClear == 2)
    }

    @Test("Change percentage is unavailable when previous close is zero")
    func changePercentageWhenPreviousCloseIsZero() async {
        let quote = Quote(symbol: "2330", currentPrice: 130, previousClose: 0, source: .yahooFinance, isFallback: false)
        #expect(quote.changePercentage == nil)
    }
}