import Foundation
import SwiftUI

struct HoldingsListView: View {
    @Bindable var viewModel: HoldingsViewModel
    @State private var showLotEditor = false

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
                        Section {
                            HoldingSummaryRow(
                                metrics: viewModel.metrics(for: holding),
                                lots: holding.lots
                            )
                        }
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
        .task {
            await viewModel.onScreenAppeared()
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
        }
    }
}

private struct HoldingSummaryRow: View {
    let metrics: HoldingMetrics
    let lots: [Lot]
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(metrics.symbol).font(.headline)
                Spacer()
                Text(metrics.currentPrice.map { Format.decimal($0) } ?? "無報價")
                    .font(.headline.monospacedDigit())
                if metrics.isUsingFallbackPrice {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("使用收盤價備援")
                }
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
            }

            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(lots) { lot in
                    LotRowView(row: LotRowViewModel(lot: lot))
                }
            } label: {
                Text("\(isExpanded ? "收合" : "展開") \(lots.count) 個批次")
                    .font(.footnote)
            }
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
                HStack {
                    Text("單價 \(row.pricePerShareText)")
                    Text("費用 \(row.feesText)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}