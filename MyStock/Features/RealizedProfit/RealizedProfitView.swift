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
                    LabeledContent("已實現損益") {
                        Text(viewModel.realizedText)
                            .font(.headline)
                            .foregroundStyle(color(for: viewModel.result?.realizedTotal))
                    }
                    LabeledContent("筆數", value: viewModel.saleCountText)
                    LabeledContent("扣除費用與稅", value: viewModel.deductionText)
                }

                if let result = viewModel.result, !result.bySymbol.isEmpty {
                    Section("依代號") {
                        ForEach(result.bySymbol, id: \.symbol) { group in
                            LabeledContent(label(for: group.symbol)) {
                                Text(Format.signedDecimal(group.realizedTotal))
                                    .foregroundStyle(color(for: group.realizedTotal))
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
                                Text("賣出 \(sale.quantity) 股 @ \(Format.decimal(sale.pricePerShare))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("手續費 \(Format.money(sale.commission))・交易稅 \(Format.money(sale.transactionTax))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ForEach(sale.allocations, id: \.lotDate) { allocation in
                                    Text("配對 \(Format.date(allocation.lotDate)) \(allocation.quantity) 股 → \(Format.signedDecimal(allocation.realizedResult))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
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

    private func color(for value: Decimal?) -> Color {
        guard let value else { return .secondary }
        if value > 0 { return .red }
        if value < 0 { return .green }
        return .primary
    }
}