import SwiftUI

struct HoldingsView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "尚無持股",
                systemImage: "chart.line.uptrend.xyaxis"
            )
            .navigationTitle("持股")
        }
    }
}
