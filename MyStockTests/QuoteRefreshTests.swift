import Foundation
import Testing
@testable import MyStock

@MainActor
@Suite("Quote refresh timing")
struct QuoteRefreshTests {
    private func lotsFor(_ symbol: String) -> [Lot] {
        [
            Lot(symbol: symbol, lotDate: Fixtures.makeDate(2026, 1, 10), quantity: 1000, pricePerShare: 150, totalFees: 1425),
            Lot(symbol: symbol, lotDate: Fixtures.makeDate(2026, 2, 20), quantity: 1000, pricePerShare: 90, totalFees: 1350)
        ]
    }

    @Test("Appearances and pull to refresh fetch once each")
    func appearancesAndPullToRefresh() async {
        let client = FakeHTTPClient()
        await client.stub(
            host: "query1.finance.yahoo.com",
            result: .success(Data(StubResponse.yahooSuccess.utf8))
        )
        let viewModel = HoldingsViewModel(quoteService: QuoteService(client: client))
        viewModel.load(lots: lotsFor("2330"))

        await viewModel.onScreenAppeared()
        let afterFirstAppearance = await client.requestCount()
        viewModel.load(lots: lotsFor("2330"))
        await viewModel.onScreenAppeared()
        let afterSecondAppearance = await client.requestCount()
        await viewModel.onPullToRefresh()
        let afterPullToRefresh = await client.requestCount()

        #expect(afterFirstAppearance == 1)
        #expect(afterSecondAppearance == 1)
        #expect(afterPullToRefresh == 2)
    }

    @Test("Recomputing figures from held prices makes no request")
    func recomputationMakesNoRequest() async {
        let client = FakeHTTPClient()
        await client.stub(
            host: "query1.finance.yahoo.com",
            result: .success(Data(StubResponse.yahooSuccess.utf8))
        )
        let viewModel = HoldingsViewModel(quoteService: QuoteService(client: client))
        viewModel.load(lots: lotsFor("2330"))
        await viewModel.onScreenAppeared()
        let afterAppeared = await client.requestCount()

        _ = HoldingCalculator.currentHoldings(from: viewModel.lots)
        _ = viewModel.holdings.map(\.averageCostPerShare)
        _ = viewModel.holdings.map { $0.totalQuantity }
        let afterComputations = await client.requestCount()

        #expect(afterAppeared == 1)
        #expect(afterComputations == 1)
    }

    @Test("No request is made when nothing is held")
    func noRequestWithoutHoldings() async {
        let client = FakeHTTPClient()
        await client.stub(
            host: "query1.finance.yahoo.com",
            result: .success(Data(StubResponse.yahooSuccess.utf8))
        )
        let viewModel = HoldingsViewModel(quoteService: QuoteService(client: client))
        viewModel.load(lots: [])

        await viewModel.onScreenAppeared()
        await viewModel.onPullToRefresh()

        #expect(await client.requestCount() == 0)
        #expect(viewModel.holdings.isEmpty)
        #expect(viewModel.quotes.isEmpty)
    }

    @Test("A symbol with no available price is reported")
    func unavailableSymbolIsReported() async {
        let client = FakeHTTPClient()
        await client.stub(host: "query1.finance.yahoo.com", result: .failure(StubError.offline))
        await client.stub(host: "www.twse.com.tw", result: .failure(StubError.offline))
        await client.stub(host: "www.tpex.org.tw", result: .failure(StubError.offline))
        let viewModel = HoldingsViewModel(quoteService: QuoteService(client: client))
        viewModel.load(lots: lotsFor("2330"))

        await viewModel.onScreenAppeared()

        #expect(viewModel.quoteUnavailableSymbols == ["2330"])
        #expect(viewModel.quotes["2330"]?.isAvailable == false)
        #expect(viewModel.loadError != nil)
    }
}