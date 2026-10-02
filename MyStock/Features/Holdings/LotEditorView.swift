import SwiftUI
import SwiftData

struct LotEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = LotEditorViewModel()
    let holdingsViewModel: HoldingsViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("批次") {
                    TextField("股票代號", text: $viewModel.symbol)
                        .textInputAutocapitalization(.characters)
                    DatePicker("批次日期", selection: $viewModel.lotDate, displayedComponents: .date)
                    Toggle("配股", isOn: $viewModel.isStockAllocation)
                }

                Section {
                    TextField("股數", text: $viewModel.quantityText)
                        .keyboardType(.numberPad)
                    if !viewModel.isStockAllocation {
                        TextField("單價", text: $viewModel.pricePerShareText)
                            .keyboardType(.decimalPad)
                    }
                } header: {
                    Text(viewModel.isStockAllocation ? "配股批次" : "買進批次")
                } footer: {
                    Text(
                        viewModel.isStockAllocation
                            ? "配股批次成本與費用記為 0，計入持股總數，但不會出現在賣出配對候選清單。"
                            : "費用依設定費率於建立當下計算並固定寫入此批次。"
                    )
                }
            }
            .navigationTitle("新增批次")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        viewModel.save(context: context)
                        if viewModel.savedLotSymbol != nil {
                            dismiss()
                        }
                    }
                    .disabled(!viewModel.canSave(context: context))
                }
            }
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
}