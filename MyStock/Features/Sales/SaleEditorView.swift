import SwiftUI
import SwiftData

struct SaleEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = SaleEditorViewModel()
    let lots: [Lot]

    var body: some View {
        NavigationStack {
            Form {
                saleSection
                allocationSection
                if !viewModel.allocationSummary.isEmpty {
                    resultSection
                }
            }
            .navigationTitle("記錄賣出")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: prepare)
            .onChange(of: viewModel.selectedSymbol) { _, _ in
                viewModel.loadCandidates(from: lots)
                viewModel.recalculate(context: context)
            }
            .toolbar { toolbarContent }
            .alert(
                "無法儲存",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                )
            ) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var saleSection: some View {
        Section("賣出") {
            Picker("股票代號", selection: $viewModel.selectedSymbol) {
                Text("請選擇").tag("")
                ForEach(allSymbols, id: \.self) { symbol in
                    Text(label(for: symbol)).tag(symbol)
                }
            }
            DatePicker("賣出日期", selection: $viewModel.saleDate, displayedComponents: .date)
            TextField("股數", text: $viewModel.quantityText)
                .keyboardType(.numberPad)
                .onChange(of: viewModel.quantityText) { _, _ in viewModel.recalculate(context: context) }
            TextField("賣價", text: $viewModel.pricePerShareText)
                .keyboardType(.decimalPad)
                .onChange(of: viewModel.pricePerShareText) { _, _ in viewModel.recalculate(context: context) }
        }
    }

    private var allocationSection: some View {
        Section {
            if viewModel.candidates.isEmpty {
                Text("沒有可配對的買進批次")
                    .foregroundStyle(.secondary)
            }
            ForEach(viewModel.candidates) { lot in
                lotRow(lot)
            }
        } header: {
            Text("配對批次")
        } footer: {
            VStack(alignment: .leading) {
                Text("必須逐批指定股數，系統不提供預設配對。配股批次不會出現在此清單。")
                if viewModel.unallocatedQuantity > 0 {
                    Text("尚有 \(viewModel.unallocatedQuantity) 股未分配")
                        .foregroundStyle(.orange)
                } else if viewModel.unallocatedQuantity < 0 {
                    Text("分配超出賣出股數 \(-viewModel.unallocatedQuantity) 股")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func lotRow(_ lot: Lot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Format.date(lot.lotDate))
                Spacer()
                Text("剩餘 \(lot.remainingQuantity) 股")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // A code and a date do not tell the user what they paid, which they
            // need in order to sanity check the sale price they are typing.
            HStack(spacing: 12) {
                LabeledContent("買進") { Text(Format.decimal(lot.pricePerShare)) }
                LabeledContent("每股成本") { Text(Format.decimal(lot.costPerShare)) }
            }
            .font(.caption)
            TextField("配對股數", text: Binding(
                get: { viewModel.allocations[lot.id] ?? "" },
                set: { viewModel.allocations[lot.id] = $0 }
            ))
            .keyboardType(.numberPad)
            .onChange(of: viewModel.allocations[lot.id] ?? "") { _, _ in
                viewModel.recalculate(context: context)
            }
        }
    }

    private var resultSection: some View {
        Section {
            ForEach(viewModel.allocationSummary, id: \.lotDate) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent(Format.date(entry.lotDate)) {
                        Text(Format.signedDecimal(entry.realizedResult))
                            .foregroundStyle(entry.realizedResult < 0 ? .green : .red)
                    }
                    // The original purchase price, so the user can judge the
                    // sale price against it without leaving this screen.
                    Text("買進 \(Format.decimal(entry.lotCostPerShare))／賣出 \(Format.decimal(entry.salePricePerShare)) × \(entry.quantity) 股")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent("合計") {
                Text(Format.signedDecimal(viewModel.totalAllocationResult))
                    .font(.headline)
            }
        } header: {
            Text("各批次已實現損益")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("儲存") {
                viewModel.save(context: context)
                if viewModel.savedSaleID != nil {
                    dismiss()
                }
            }
            .disabled(!viewModel.canSave(context: context))
        }
    }

    private var allSymbols: [String] {
        Array(Set(lots.map(\.symbol))).sorted()
    }

    private func label(for symbol: String) -> String {
        guard let name = StockStore.name(for: symbol, in: context), !name.isEmpty else {
            return symbol
        }
        return "\(symbol) \(name)"
    }

    private func prepare() {
        if viewModel.selectedSymbol.isEmpty {
            viewModel.selectedSymbol = allSymbols.first ?? ""
        }
        viewModel.loadCandidates(from: lots)
        viewModel.recalculate(context: context)
    }
}