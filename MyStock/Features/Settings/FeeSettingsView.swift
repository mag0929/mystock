import SwiftUI
import SwiftData

struct FeeSettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var viewModel = FeeSettingsViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("費率") {
                    HStack {
                        Text("手續費率")
                        Spacer()
                        TextField("0.1425", text: $viewModel.commissionRateText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text("%")
                    }
                    HStack {
                        Text("交易稅率")
                        Spacer()
                        TextField("0.3", text: $viewModel.transactionTaxRateText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text("%")
                    }
                }

                Section {
                    Text("手續費買賣雙方都會收取，小數無條捨去至整元，因此買進批次的費用等於成交金額 × 手續費率取整數。")
                    Text("交易稅只在賣出時課徵，不會算進買進批次的成本。")
                    Text("證交稅 0.4% 於年度結算時申報，不在每筆交易扣除，僅作為參考值記錄。")
                    Text("費率只會套用到儲存之後建立的批次與賣出，既有資料不會被改變。")
                }
            }
            .navigationTitle("設定")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        viewModel.save(context: context)
                    }
                    .disabled(!viewModel.canSave)
                }
            }
            .task { viewModel.load(context: context) }
            .alert(
                "費率設定",
                isPresented: Binding(
                    get: { viewModel.statusMessage != nil || viewModel.saveErrorMessage != nil },
                    set: {
                        if !$0 {
                            viewModel.statusMessage = nil
                            viewModel.saveErrorMessage = nil
                        }
                    }
                )
            ) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(viewModel.saveErrorMessage ?? viewModel.statusMessage ?? "")
            }
        }
    }
}