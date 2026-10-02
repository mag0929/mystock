import Foundation
import SwiftData

@MainActor
@Observable
final class RealizedProfitViewModel {
    var period: RealizedQueryPeriod = .currentMonth
    var customStart: Date = Date()
    var customEnd: Date = Date()
    private(set) var result: RealizedQueryResult?

    private let container: ModelContainer?

    init(container: ModelContainer? = nil) {
        self.container = container
    }

    var periodOptions: [(title: String, period: RealizedQueryPeriod)] {
        [
            ("當日", .today),
            ("當月", .currentMonth),
            ("前三個月", .previousThreeMonths),
            ("自訂區間", .custom(from: customStart, to: customEnd))
        ]
    }

    func load(context: ModelContext, now: Date = Date()) {
        let sales = (try? context.fetch(FetchDescriptor<Sale>())) ?? []
        var allocationsBySaleID: [UUID: [SaleAllocation]] = [:]
        for sale in sales {
            allocationsBySaleID[sale.id] = (try? SaleStore.allocations(for: sale, in: context)) ?? []
        }
        result = RealizedQueryService.run(
            period: period,
            sales: sales,
            allocationsBySaleID: allocationsBySaleID,
            now: now
        )
    }

    var realizedText: String {
        guard let result else { return "—���" }
        return Format.signedDecimal(result.realizedTotal)
    }

    var saleCountText: String {
        guard let result else { return "0 筆" }
        return "\(result.saleCount) 筆"
    }

    var deductionText: String {
        guard let result else { return "—" }
        return Format.decimal(result.totalDeductions)
    }
}