import Foundation
import SwiftUI

struct HoldingsListView: View {
    @Bindable var viewModel: HoldingsViewModel
    let lots: [Lot]
    @State private var showLotEditor = false
    @State private var editingLot: Lot?
    @State private var lotPendingDeletion: Lot?
    @State private var deletionMessage: String?
    @State private var errorMessage: String?
    @State private var expandedSymbols: Set<String> = []
    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack {
            List {
                if let summary = viewModel.portfolioSummary {
                    PortfolioSummarySection(summary: summary)
                }

                if viewModel.holdings.isEmpty {
                    EmptyHoldingsState { showLotEditor = true }
                } else {
                    ForEach(viewModel.holdings) { holding in
                        holdingSection(for: holding)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("持股")
            .refreshable {
                await viewModel.onPullToRefresh()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showLotEditor = true
                    } label: {
                        Label("新增批次", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showLotEditor) {
            LotEditorView(holdingsViewModel: viewModel)
        }
        .sheet(item: $editingLot) { lot in
            LotEditorView(holdingsViewModel: viewModel, lot: lot)
        }
        .task(id: lotsSignature) {
            await viewModel.loadAndRefresh(lots: lots, context: context)
        }
        .confirmationDialog(
            "刪除批次",
            isPresented: Binding(
                get: { lotPendingDeletion != nil },
                set: { if !$0 { lotPendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: lotPendingDeletion
        ) { lot in
            Button("刪除", role: .destructive) { delete(lot) }
            Button("取消", role: .cancel) {}
        } message: { lot in
            Text(deletionMessage ?? "")
        }
        .overlay {
            if viewModel.isRefreshing {
                ProgressView()
            }
        }
        .alert(
            "報價取得失敗",
            isPresented: Binding(
                get: { viewModel.loadError != nil },
                set: { if !$0 { viewModel.dismissLoadError() } }
            )
        ) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("將沿用先前價格計算損益")
        }
        .alert(
            "操作失敗",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// Reloading on `lots.count` alone would miss an edit that keeps the same number
    /// of lots, such as correcting a quantity, and the figures would stay stale.
    private var lotsSignature: String {
        lots
            .map { "\($0.id.uuidString):\($0.quantity):\($0.remainingQuantity)" }
            .joined(separator: "|")
    }

    @ViewBuilder
    private func holdingSection(for holding: HoldingCalculator.Holding) -> some View {
        let isExpanded = expandedSymbols.contains(metricsSymbol(for: holding))
        Section {
            HoldingSummaryRow(
                metrics: viewModel.metrics(for: holding),
                lots: holding.lots,
                isExpanded: isExpanded,
                onToggleExpand: { toggle(holding) }
            )
            if isExpanded {
                ForEach(holding.lots) { lot in
                    lotRow(for: lot)
                }
            }
        }
    }

    private func lotRow(for lot: Lot) -> some View {
        LotRowView(row: viewModel.lotRow(for: lot, context: context))
            .contentShape(Rectangle())
            .onTapGesture { editingLot = lot }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    confirmDeletion(of: lot)
                } label: {
                    Label("刪除", systemImage: "trash")
                }
                .accessibilityIdentifier("holdings.deleteLot")
            }
    }

    private func metricsSymbol(for holding: HoldingCalculator.Holding) -> String {
        holding.lots.first?.symbol ?? ""
    }

    private func toggle(_ holding: HoldingCalculator.Holding) {
        let symbol = metricsSymbol(for: holding)
        if expandedSymbols.contains(symbol) {
            expandedSymbols.remove(symbol)
        } else {
            expandedSymbols.insert(symbol)
        }
    }

    private func confirmDeletion(of lot: Lot) {
        let allocations = (try? LotStore.allocations(for: lot, in: context)) ?? []
        if allocations.isEmpty {
            deletionMessage = "將一併移除這個批次。"
        } else {
            let shares = allocations.reduce(0) { $0 + $1.quantity }
            deletionMessage = "這個批次已參與 \(allocations.count) 筆賣出、共 \(shares) 股。刪除後那些賣出紀錄的配對也會被移除，已實現損益會跟著變動。"
        }
        lotPendingDeletion = lot
    }

    private func delete(_ lot: Lot) {
        lotPendingDeletion = nil
        deletionMessage = nil
        do {
            try LotStore.delete(lot, in: context)
            Task { await viewModel.loadAndRefresh(lots: lots.filter { $0.id != lot.id }, context: context) }
        } catch {
            errorMessage = "刪除失敗：\(error.localizedDescription)"
        }
    }
}

private struct EmptyHoldingsState: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "尚無持股",
                systemImage: "chart.line.uptrend.xyaxis",
                description: Text("記錄每一筆買進與配股批次，即可追蹤成本與損益")
            )
            Button(action: onAdd) {
                Label("新增批次", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)
            .accessibilityIdentifier("holdings.addFirstLot")
        }
        .listRowSeparator(.hidden)
    }
}

private struct PortfolioSummarySection: View {
    let summary: PortfolioSummary

    var body: some View {
        Section("總覽") {
            LabeledContent("當前漲幅") {
                Text(summary.priceChangeText ?? "不可用")
                    .foregroundStyle(summary.priceChangeColor)
            }
            LabeledContent("單日收益") {
                Text(summary.singleDayText ?? "不可用")
                    .foregroundStyle(summary.singleDayColor)
            }
            LabeledContent("持有收益") {
                Text(summary.holdingText ?? "不可用")
                    .foregroundStyle(summary.holdingColor)
            }
            if summary.excludedSymbolCount > 0 {
                LabeledContent("排除標的") {
                    Text("\(summary.excludedSymbolCount) 檔無報價")
                        .foregroundStyle(.secondary)
                }
            }
            SectionFooterNote(text: Self.netOfFeesNote)
        }
    }

    /// Without this the user reads 持有收益 as a gross gain, then finds a sale
    /// nets out smaller than the figure they were shown.
    private static let netOfFeesNote = "持有收益與批次損益已依設定費率扣除估計賣出手續費與交易稅"
}

/// The same note where the figures appear, so a holding row is not read
/// differently from the total above it.
private struct SectionFooterNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}

private struct HoldingSummaryRow: View {
    let metrics: HoldingMetrics
    let lots: [Lot]
    let isExpanded: Bool
    let onToggleExpand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(metrics.symbol).font(.headline)
                if let name = metrics.displayName, !name.isEmpty {
                    Text(name).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Text(Format.decimal(Decimal(metrics.totalQuantity), fractionDigits: 0) + " 股")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if metrics.isUsingFallbackPrice {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("使用收盤價備援")
                }
            }

            HStack {
                metricLabel(
                    "均價",
                    metrics.averageCostPerShare.map { Format.decimal($0) } ?? "不可用"
                )
                Spacer()
                metricLabel("現價", metrics.currentPrice.map { Format.decimal($0) } ?? "無報價")
            }

            HStack(spacing: 16) {
                metricLabel("漲幅", metrics.priceChangePercentage.map { Format.percent($0) } ?? "不可用")
                metricLabel(
                    "單日收益",
                    metrics.singleDayResult.map { Format.signedDecimal($0) } ?? "不可用"
                )
                metricLabel(
                    "持有收益",
                    metrics.holdingResult.map { Format.signedDecimal($0) } ?? "不可用"
                )
                metricLabel(
                    "報酬率",
                    metrics.holdingReturnPercentage.map { Format.percent($0) } ?? "不可用"
                )
            }

            Text("持有收益與批次損益已依設定費率扣除估計賣出手續費與交易稅")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                Text("\(isExpanded ? "收合" : "展開") \(lots.count) 個批次")
                    .font(.footnote)
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
            .onTapGesture { onToggleExpand() }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("holdings.toggleLots")
            .accessibilityAddTraits(.isButton)
        }
        .padding(.vertical, 4)
    }

    private func metricLabel(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.monospacedDigit())
        }
    }
}

struct LotRowView: View {
    let row: LotRowViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Symbol and name, so a row still says what it is when read on
                // its own rather than only under its holding heading.
                Text(row.symbol).font(.subheadline.weight(.medium))
                if let name = row.displayName, !name.isEmpty {
                    Text(name).font(.caption).foregroundStyle(.secondary)
                }
                Text(Format.date(row.lotDate)).font(.subheadline)
                Text(row.typeText)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(row.costFieldsAvailable ? Color.accentColor.opacity(0.15) : Color.orange.opacity(0.2))
                    .clipShape(Capsule())
                Spacer()
                Text("剩餘 \(row.remainingText) / \(row.quantityText)").font(.caption)
            }
            if row.costFieldsAvailable {
                // The purchase figures and the current figures on one row, so
                // the user can see what a lot cost and what it is worth without
                // matching rows against each other.
                HStack {
                    Text("成交價 \(row.pricePerShareText)")
                    Text("手續費 \(row.commissionText)")
                    Text("持有成本 \(row.remainingCostText)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack {
                    Text("時價 \(row.currentPriceText)")
                    Text("市價 \(row.marketValueText)")
                    Spacer()
                    Text("損益 \(row.resultText)")
                        .foregroundStyle(color(for: row.resultColorValue))
                    Text("報酬率 \(row.returnText)")
                        .foregroundStyle(color(for: row.resultColorValue))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func color(for value: Decimal?) -> Color {
        guard let value else { return .secondary }
        if value > 0 { return .red }
        if value < 0 { return .green }
        return .primary
    }
}
