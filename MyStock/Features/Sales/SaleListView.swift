import SwiftUI

struct SaleListView: View {
    let lots: [Lot]
    @State private var showEditor = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(saleAllocationCandidatesBySymbol, id: \.symbol) { entry in
                    Section(entry.symbol) {
                        ForEach(entry.lots) { lot in
                            LotRowView(row: LotRowViewModel(lot: lot))
                        }
                    }
                }
            }
            .navigationTitle("賣出")
            .refreshable {}
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showEditor = true
                    } label: {
                        Label("記錄賣出", systemImage: "plus")
                    }
                    .disabled(lots.isEmpty)
                }
            }
            .sheet(isPresented: $showEditor) {
                SaleEditorView(lots: lots)
            }
            .overlay {
                if lots.isEmpty {
                    ContentUnavailableView(
                        "尚無可賣出批次",
                        systemImage: "cart",
                        description: Text("請先在持股頁新增買進批次")
                    )
                }
            }
        }
    }

    private var saleAllocationCandidatesBySymbol: [(symbol: String, lots: [Lot])] {
        let symbols = Set(lots.map(\.symbol)).sorted()
        return symbols.compactMap { symbol in
            let candidates = HoldingCalculator.saleAllocationCandidates(from: lots, symbol: symbol)
            return candidates.isEmpty ? nil : (symbol, candidates)
        }
    }
}