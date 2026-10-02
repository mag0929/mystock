import Foundation
import SwiftData
import Testing
@testable import MyStock

@MainActor
@Suite("Holdings screen presentation")
struct HoldingsPresentationTests {
    private func lots() -> [Lot] {
        [
            Lot(symbol: "2330", lotDate: Fixtures.makeDate(2026, 1, 10), quantity: 1000, pricePerShare: 150),
            Lot(symbol: "2330", lotDate: Fixtures.makeDate(2026, 2, 20), quantity: 1000, pricePerShare: 90),
            Lot(symbol: "2330", lotDate: Fixtures.makeDate(2026, 4, 1), quantity: 200, pricePerShare: 0, lotType: .stockAllocation)
        ]
    }

    private func pricedViewModel() async -> HoldingsViewModel {
        let client = FakeHTTPClient()
        await client.stub(
            host: "query1.finance.yahoo.com",
            result: .success(Data(StubResponse.yahooSuccess.utf8))
        )
        let viewModel = HoldingsViewModel(quoteService: QuoteService(client: client))
        viewModel.load(lots: lots())
        await viewModel.onScreenAppeared()
        return viewModel
    }

    @Test("Per symbol rows show price and the three figures")
    func rowsShowFigures() async {
        let viewModel = await pricedViewModel()
        let metrics = viewModel.metrics(for: viewModel.holdings[0])

        #expect(viewModel.holdings.count == 1)
        #expect(metrics.symbol == "2330")
        #expect(metrics.currentPrice == 130)
        #expect(metrics.totalQuantity == 2200)
        #expect(metrics.holdingResult == 46000)
        #expect(metrics.singleDayResult == 11000)
    }

    @Test("Per lot rows show the stock allocation type and hide its costs")
    func lotRowsShowTypeIndicator() async {
        let viewModel = await pricedViewModel()
        let rows = viewModel.holdings[0].lots.map(LotRowViewModel.init(lot:))

        #expect(rows.count == 3)
        #expect(rows.map(\.typeText) == ["買進", "買進", "配股"])
        #expect(rows.last?.costFieldsAvailable == false)
        #expect(rows.last?.remainingText == "200")
    }

    @Test("Portfolio summary matches the unit test calculation")
    func portfolioSummaryMatchesCalculation() async {
        let viewModel = await pricedViewModel()
        let summary = viewModel.portfolioSummary

        #expect(summary?.holdingText == "+46,000")
        #expect(summary?.singleDayText == "+11,000")
        #expect(summary?.excludedSymbolCount == 0)
    }

    @Test("Portfolio summary reports excluded symbols")
    func portfolioSummaryReportsExclusions() async {
        let client = FakeHTTPClient()
        await client.stub(host: "query1.finance.yahoo.com", result: .failure(StubError.offline))
        await client.stub(host: "www.twse.com.tw", result: .failure(StubError.offline))
        await client.stub(host: "www.tpex.org.tw", result: .failure(StubError.offline))
        let viewModel = HoldingsViewModel(quoteService: QuoteService(client: client))
        viewModel.load(lots: lots())
        await viewModel.onScreenAppeared()
        let summary = viewModel.portfolioSummary

        #expect(summary?.excludedSymbolCount == 1)
        #expect(summary?.holdingText == "+0")
        #expect(viewModel.quoteUnavailableSymbols == ["2330"])
    }

    @Test("Empty holdings produce no portfolio summary")
    func emptyHoldingsProduceNoSummary() {
        let viewModel = HoldingsViewModel()
        viewModel.load(lots: [])

        #expect(viewModel.portfolioSummary == nil)
        #expect(viewModel.holdings.isEmpty)
    }

    @Test("A fallback priced symbol is flagged on the row")
    func fallbackPricedSymbolIsFlagged() async {
        let client = FakeHTTPClient()
        await client.stub(host: "query1.finance.yahoo.com", result: .failure(StubError.offline))
        await client.stub(
            host: "www.twse.com.tw",
            result: .success(Data(StubResponse.twseClose("128.00").utf8))
        )
        let viewModel = HoldingsViewModel(quoteService: QuoteService(client: client))
        viewModel.load(lots: lots())
        await viewModel.onScreenAppeared()
        let metrics = viewModel.metrics(for: viewModel.holdings[0])

        #expect(metrics.isUsingFallbackPrice == true)
        #expect(metrics.currentPrice == 128)
        #expect((metrics.holdingResult ?? .zero).rounded(scale: 2) == Decimal(41600))
    }

    @Test("Stock allocation lots are not offered as sale candidates")
    func stockAllocationNotOfferedAsSaleCandidate() async {
        let viewModel = await pricedViewModel()
        let candidates = HoldingCalculator.saleAllocationCandidates(from: viewModel.lots, symbol: "2330")

        #expect(candidates.count == 2)
        #expect(candidates.allSatisfy { $0.lotType == .buy })
    }

    @Test("Lot editor records a stock allocation lot with zero cost")
    func lotEditorRecordsStockAllocation() throws {
        let container = try Persistence.makeInMemoryContainer()
        let context = ModelContext(container)
        let viewModel = LotEditorViewModel()
        viewModel.symbol = " 2330 "
        viewModel.lotDate = Fixtures.makeDate(2026, 4, 1)
        viewModel.quantityText = "200"
        viewModel.isStockAllocation = true

        #expect(viewModel.canSave(context: context) == true)
        viewModel.save(context: context)

        let saved = try context.fetch(FetchDescriptor<Lot>())
        #expect(viewModel.errorMessage == nil)
        #expect(saved.count == 1)
        #expect(saved[0].lotType == .stockAllocation)
        #expect(saved[0].symbol == "2330")
        #expect(saved[0].totalCost == 0)
        #expect(saved[0].totalFees == 0)
    }

    @Test("Lot editor charges fees when recording a buy lot")
    func lotEditorChargesFees() throws {
        let container = try Persistence.makeInMemoryContainer()
        let context = ModelContext(container)
        let viewModel = LotEditorViewModel()
        viewModel.symbol = "2330"
        viewModel.quantityText = "1000"
        viewModel.pricePerShareText = "150"

        viewModel.save(context: context)

        let saved = try context.fetch(FetchDescriptor<Lot>())
        #expect(saved[0].totalFees > 0)
        #expect(saved[0].totalCost == Decimal(150000) + saved[0].totalFees)
    }

    @Test("Lot editor rejects a non positive quantity")
    func lotEditorRejectsBadQuantity() throws {
        let container = try Persistence.makeInMemoryContainer()
        let context = ModelContext(container)
        let viewModel = LotEditorViewModel()
        viewModel.symbol = "2330"
        viewModel.quantityText = "0"
        viewModel.pricePerShareText = "150"

        #expect(viewModel.canSave(context: context) == false)
        viewModel.save(context: context)

        #expect(viewModel.errorMessage != nil)
        #expect(try context.fetch(FetchDescriptor<Lot>()).isEmpty)
    }
}