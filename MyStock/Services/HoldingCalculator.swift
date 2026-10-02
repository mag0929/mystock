import Foundation
import SwiftData

enum HoldingCalculator {
    struct Holding: Identifiable {
        let symbol: String
        let lots: [Lot]
        var displayName: String?

        var id: String { symbol }

        var totalQuantity: Int {
            lots.reduce(0) { $0 + $1.remainingQuantity }
        }

        var totalRemainingCost: Decimal {
            lots.reduce(Decimal.zero) { $0 + $1.remainingCost }
        }

        var averageCostPerShare: Decimal? {
            guard totalQuantity > 0 else { return nil }
            return totalRemainingCost / Decimal(totalQuantity)
        }
    }

    static func holdings(from lots: [Lot]) -> [Holding] {
        let grouped = Dictionary(grouping: lots, by: \.symbol)
        return grouped
            .map { Holding(symbol: $0.key, lots: $0.value.sorted { $0.lotDate < $1.lotDate }) }
            .sorted { $0.symbol < $1.symbol }
    }

    static func currentHoldings(from lots: [Lot]) -> [Holding] {
        holdings(from: lots).filter { $0.totalQuantity > 0 }
    }

    static func saleAllocationCandidates(from lots: [Lot], symbol: String) -> [Lot] {
        lots
            .filter { $0.symbol == symbol && $0.isAllocatableForSale }
            .sorted { $0.lotDate < $1.lotDate }
    }
}
