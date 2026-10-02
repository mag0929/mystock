import SwiftUI
import SwiftData
import Testing
@testable import MyStock

@MainActor
@Suite("Screen rendering")
struct ScreenRenderingTests {
    private func imageRenderer<V: View>(_ view: V) {
        let renderer = ImageRenderer(content: view.frame(width: 390, height: 300))
        renderer.scale = 2
        renderer.render { _, _ in }
    }

    @Test("Holdings screen renders with holdings and prices")
    func holdingsScreenRenders() async throws {
        let lots = [
            Lot(symbol: "2330", lotDate: Fixtures.makeDate(2026, 1, 10), quantity: 1000, pricePerShare: 150),
            Lot(symbol: "2330", lotDate: Fixtures.makeDate(2026, 2, 20), quantity: 1000, pricePerShare: 90),
            Lot(symbol: "2330", lotDate: Fixtures.makeDate(2026, 4, 1), quantity: 200, pricePerShare: 0, lotType: .stockAllocation)
        ]
        let client = FakeHTTPClient()
        await client.stub(
            host: "query1.finance.yahoo.com",
            result: .success(Data(StubResponse.yahooSuccess.utf8))
        )
        let viewModel = HoldingsViewModel(quoteService: QuoteService(client: client))
        await viewModel.loadAndRefresh(lots: lots)

        imageRenderer(HoldingsListView(viewModel: viewModel, lots: lots))
    }

    @Test("Holdings screen renders its empty state")
    func holdingsEmptyStateRenders() {
        let viewModel = HoldingsViewModel()
        viewModel.load(lots: [])

        imageRenderer(HoldingsListView(viewModel: viewModel, lots: []))
    }

    @Test("Lot row renders for both lot types")
    func lotRowRendersForBothTypes() {
        let buy = Lot(symbol: "2330", lotDate: Fixtures.makeDate(2026, 1, 10), quantity: 1000, pricePerShare: 150, totalFees: 1425)
        let allocation = Lot(symbol: "2330", lotDate: Fixtures.makeDate(2026, 4, 1), quantity: 200, pricePerShare: 0, lotType: .stockAllocation)

        imageRenderer(LotRowView(row: LotRowViewModel(lot: buy)))
        imageRenderer(LotRowView(row: LotRowViewModel(lot: allocation)))
    }

    @Test("Sale editor renders candidates without stock allocation lots")
    func saleEditorRenders() throws {
        let container = try Persistence.makeInMemoryContainer()
        let context = ModelContext(container)
        let lots = [
            Lot(symbol: "2330", lotDate: Fixtures.makeDate(2026, 1, 10), quantity: 1000, pricePerShare: 150),
            Lot(symbol: "2330", lotDate: Fixtures.makeDate(2026, 2, 20), quantity: 1000, pricePerShare: 90),
            Lot(symbol: "2330", lotDate: Fixtures.makeDate(2026, 4, 1), quantity: 200, pricePerShare: 0, lotType: .stockAllocation)
        ]
        for lot in lots { context.insert(lot) }
        try context.save()

        imageRenderer(SaleEditorView(lots: lots).environment(\.modelContext, context))
    }

    @Test("Sale list renders")
    func saleListRenders() {
        let lots = [
            Lot(symbol: "2330", lotDate: Fixtures.makeDate(2026, 1, 10), quantity: 1000, pricePerShare: 150),
            Lot(symbol: "2330", lotDate: Fixtures.makeDate(2026, 4, 1), quantity: 200, pricePerShare: 0, lotType: .stockAllocation)
        ]
        imageRenderer(SaleListView(lots: lots))
    }

    @Test("Realized profit screen renders a query result")
    func realizedProfitScreenRenders() throws {
        let container = try Persistence.makeInMemoryContainer()
        let context = ModelContext(container)
        let lot = Lot(symbol: "2330", lotDate: Fixtures.makeDate(2026, 1, 10), quantity: 1000, pricePerShare: 90)
        context.insert(lot)
        try SaleStore.save(
            symbol: "2330",
            saleDate: Date(),
            quantity: 1000,
            pricePerShare: 130,
            drafts: [DraftAllocation(lot: lot, quantity: 1000)],
            rates: FeeRates(commissionRate: Decimal(string: "0.001425") ?? .zero, transactionTaxRate: Decimal(string: "0.003") ?? .zero),
            in: context
        )

        imageRenderer(RealizedProfitView().environment(\.modelContext, context))
    }

    @Test("Fee settings screen renders")
    func feeSettingsScreenRenders() throws {
        let container = try Persistence.makeInMemoryContainer()
        let context = ModelContext(container)

        imageRenderer(FeeSettingsView().environment(\.modelContext, context))
    }

    @Test("Main tab view renders")
    func mainTabViewRenders() {
        imageRenderer(
            MainTabView(lots: [Lot(symbol: "2330", lotDate: Fixtures.makeDate(2026, 1, 10), quantity: 1000, pricePerShare: 150)])
        )
    }
}