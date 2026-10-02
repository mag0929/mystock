import SwiftData
import SwiftUI

@main
struct MyStockApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(try! Persistence.makeContainer())
    }
}

struct RootView: View {
    @Query private var lots: [Lot]

    var body: some View {
        MainTabView(lots: lots)
    }
}

struct MainTabView: View {
    let lots: [Lot]
    @State private var holdingsViewModel = HoldingsViewModel()

    var body: some View {
        TabView {
            HoldingsListView(viewModel: holdingsViewModel)
                .tabItem { Label("持股", systemImage: "chart.line.uptrend.xyaxis") }
                .onAppear {
                    holdingsViewModel.load(lots: lots)
                }
                .onChange(of: lots.count) { _, _ in
                    holdingsViewModel.load(lots: lots)
                }

            SaleListView(lots: lots)
                .tabItem { Label("賣出", systemImage: "arrow.up.circle") }

            RealizedProfitView()
                .tabItem { Label("已實現損益", systemImage: "list.bullet.rectangle") }

            FeeSettingsView()
                .tabItem { Label("設定", systemImage: "gearshape") }
        }
    }
}