import SwiftUI
import SwiftData

struct LotEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: LotEditorViewModel
    let holdingsViewModel: HoldingsViewModel

    init(holdingsViewModel: HoldingsViewModel, lot: Lot? = nil) {
        self.holdingsViewModel = holdingsViewModel
        _viewModel = State(initialValue: LotEditorViewModel(lot: lot))
    }

    private var isEditing: Bool { viewModel.isEditing }

    var body: some View {
        NavigationStack {
            Form {
                Section("批次") {
                    TextField("股票代號", text: $viewModel.symbol)
                        .accessibilityIdentifier("lotEditor.symbol")
                        .textInputAutocapitalization(.characters)
                        .onChange(of: viewModel.symbol) { _, newValue in
                            Task { await viewModel.resolveName(for: newValue, context: context) }
                        }
                    stockNameField
                    DatePicker("批次日期", selection: $viewModel.lotDate, displayedComponents: .date)
                    Toggle("配股", isOn: $viewModel.isStockAllocation)
                        .disabled(isEditing)
                }

                Section {
                    TextField("股數", text: $viewModel.quantityText)
                        .accessibilityIdentifier("lotEditor.quantity")
                        .keyboardType(.numberPad)
                    if !viewModel.isStockAllocation {
                        TextField("單價", text: $viewModel.pricePerShareText)
                            .accessibilityIdentifier("lotEditor.price")
                            .keyboardType(.decimalPad)
                    }
                } header: {
                    Text(viewModel.isStockAllocation ? "配股批次" : "買進批次")
                } footer: {
                    Text(footerText)
                }
            }
            .navigationTitle(isEditing ? "編輯批次" : "新增批次")
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

    private var footerText: String {
        if isEditing {
            return "費用依建立當時的費率固定，不會因這次修改而重新計算。批次類型不可變更。"
        }
        return viewModel.isStockAllocation
            ? "配股批次成本與費用記為 0，計入持股總數，但不會出現在賣出配對候選清單。"
            : "費用依設定費率於建立當下計算並固定寫入此批次。"
    }

    @ViewBuilder
    private var stockNameField: some View {
        if viewModel.isResolvingName {
            HStack {
                Text("股票名稱")
                Spacer()
                ProgressView()
            }
        } else if viewModel.nameLookupFailed {
            VStack(alignment: .leading, spacing: 4) {
                TextField("股票名稱（查不到，請手動輸入）", text: Binding(
                    get: { viewModel.displayName },
                    set: { viewModel.updateName($0) }
                ))
                .accessibilityIdentifier("lotEditor.displayName")
                Text("查無此代號的名稱，可自行輸入後儲存。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack {
                Text("股票名稱")
                Spacer()
                TextField("可自行修正", text: Binding(
                    get: { viewModel.displayName },
                    set: { viewModel.updateName($0) }
                ))
                .accessibilityIdentifier("lotEditor.displayName")
                .multilineTextAlignment(.trailing)
            }
        }
    }
}