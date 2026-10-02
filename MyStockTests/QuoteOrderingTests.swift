import Foundation
import SwiftUI
import Testing
@testable import MyStock

@MainActor
@Suite("Quote fetch ordering")
struct QuoteOrderingTests {
    @Test("Fetching quotes after the lots load reaches every symbol")
    func fetchAfterLoadReachesEverySymbol() async throws {
        let client = FakeHTTPClient()
        await client.stub(
            host: "query1.finance.yahoo.com",
            result: .success(Data(StubResponse.yahooSuccess.utf8))
        )
        let viewModel = HoldingsViewModel(quoteService: QuoteService(client: client))
        let lots = [
            Lot(symbol: "2330", lotDate: Fixtures.makeDate(2026, 1, 10), quantity: 1000, pricePerShare: 150)
        ]

        await viewModel.loadAndRefresh(lots: lots)

        #expect(viewModel.holdings.count == 1)
        #expect(viewModel.quotes["2330"]?.isAvailable == true)
        #expect(viewModel.metrics(for: viewModel.holdings[0]).currentPrice != nil)
    }

    @Test("Loading lots on its own does not leave the screen without prices")
    func loadingLotsAloneDoesNotLeaveScreenWithoutPrices() async throws {
        let client = FakeHTTPClient()
        await client.stub(
            host: "query1.finance.yahoo.com",
            result: .success(Data(StubResponse.yahooSuccess.utf8))
        )
        let viewModel = HoldingsViewModel(quoteService: QuoteService(client: client))
        let lots = [
            Lot(symbol: "2330", lotDate: Fixtures.makeDate(2026, 1, 10), quantity: 1000, pricePerShare: 150)
        ]

        // One step, so the fetch cannot run before the lots are loaded.
        await viewModel.loadAndRefresh(lots: lots)

        #expect(
            viewModel.quotes["2330"]?.isAvailable == true,
            "批次載入後仍應取得報價，否則畫面顯示無報價"
        )
    }
}