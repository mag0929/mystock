import SwiftUI
import SwiftData

struct RealizedProfitView: View {
    @Environment(\.modelContext) private var context
    @State private var viewModel = RealizedProfitViewModel()
    @State private var showCustomRange = false

    var body: some View {
        NavigationStack {
            List {
                Section("區間") {
                    Picker("區間", selection: periodBinding) {
                        ForEach(viewModel.periodOptions, id: \.title) { option in
                            Text(option.title).tag(option.title)
                        }
                    }
                    .pickerStyle(.segmented)
                    if showCustomRange {
                        DatePicker("起始", selection: $viewModel.customStart, displayedComponents: .date)
                        DatePicker("結束", selection: $viewModel.customEnd, displayedComponents: .date)
                    }
                }

                Section("合計") {
                    LabeledContent("營業收入", value: viewModel.grossProceedsText)
                    LabeledContent("成本", value: viewModel.costBasisText)
                    LabeledContent("損益", value: viewModel.realizedText)
                        .font(.headline)
                    LabeledContent("報酬率", value: viewModel.returnPercentageText)
                    LabeledContent("筆數", value: viewModel.saleCountText)
                    LabeledContent("扣除費用與稅", value: viewModel.deductionText)
                }

                if let result = viewModel.result, !result.bySymbol.isEmpty {
                    Section("依代號") {
                        ForEach(result.bySymbol, id: \.symbol) { group in
                            VStack(alignment: .leading, spacing: 4) {
                                LabeledContent(label(for: group.symbol)) {
                                    Text(Format.signedDecimal(group.realizedTotal))
                                        .foregroundStyle(color(for: group.realizedTotal))
                                }
                                Text("營業收入 \(Format.decimal(group.grossProceedsTotal))　成本 \(Format.decimal(group.costBasisTotal))　報酬率 \(percentageText(group.returnPercentage))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let result = viewModel.result, !result.sales.isEmpty {
                    Section("逐筆") {
                        ForEach(result.sales, id: \.saleID) { sale in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(Format.date(sale.saleDate))
                                    Text(label(for: sale.symbol)).font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(Format.signedDecimal(sale.realizedResult))
                                        .foregroundStyle(color(for: sale.realizedResult))
                                }
                                .font(.subheadline)
                                Text("賣出 \(sale.quantity) 股 @ \(Format.decimal(sale.pricePerShare))　營業收入 \(Format.decimal(sale.grossProceeds))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("成本 \(Format.decimal(sale.costBasis))　損益 \(Format.signedDecimal(sale.realizedResult))　報酬率 \(percentageText(sale.returnPercentage))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("手續費 \(Format.money(sale.commission))・交易稅 \(Format.money(sale.transactionTax))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                // Behind a disclosure, because a sale that draws on several lots would
                                // otherwise bury the summary line.
                                DisclosureGroup("配對明細（\(sale.allocations.count) 筆）") {
                                    ForEach(Array(sale.allocations.enumerated()), id: \.offset) { _, allocation in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("\(Format.date(allocation.lotDate))　\(allocation.quantity) 股")
                                            Text("買進 \(Format.decimal(allocation.lotCostPerShare)) → 賣出 \(Format.decimal(allocation.salePricePerShare))　損益 \(Format.signedDecimal(allocation.realizedResult))")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        .font(.caption)
                                    }
                                }
                                .font(.caption)
                                if !sale.isCompleteAllocation {
                                    Label(
                                        "配對不足，\(sale.allocatedQuantity)/\(sale.quantity) 股",
                                        systemImage: "exclamationmark.triangle.fill"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("已實現損益")
            .task { reload() }
            .onChange(of: viewModel.period) { _, _ in reload() }
            .onChange(of: viewModel.customStart) { _, _ in reload() }
            .onChange(of: viewModel.customEnd) { _, _ in reload() }
            .overlay {
                if viewModel.result?.sales.isEmpty ?? true {
                    ContentUnavailableView(
                        "此區間沒有賣出紀錄",
                        systemImage: "tray",
                        description: Text("切換區間或前往賣出頁記錄一筆")
                    )
                }
            }
        }
    }

    private var periodBinding: Binding<RealizedQueryPeriod> {
        Binding(
            get: { viewModel.period },
            set: { newValue in
                viewModel.period = newValue
                if case .custom = newValue {
                    showCustomRange = true
                } else {
                    showCustomRange = false
                }
            }
        )
    }

    private func reload() {
        viewModel.load(context: context)
    }

    private func label(for symbol: String) -> String {
        guard let name = StockStore.name(for: symbol, in: context), !name.isEmpty else {
            return symbol
        }
        return "\(symbol) \(name)"
    }

    /// A return over a zero cost basis has no meaning, so say so rather than
    /// printing a percentage that implies one.
    private func percentageText(_ value: Decimal?) -> String {
        guard let value else { return "不適用" }
        return Format.percent(value)
    }

    private func color(for value: Decimal?) -> Color {
        guard let value else { return .secondary }
        if value > 0 { return .red }
        if value < 0 { return .green }
        return .primary
    }
}