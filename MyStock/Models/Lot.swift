import Foundation
import SwiftData

@Model
final class Lot {
    var id: UUID = UUID()
    var symbol: String = ""
    var lotDate: Date = Date(timeIntervalSince1970: 0)
    var quantity: Int = 0
    var pricePerShare: Decimal = Decimal.zero
    var totalFees: Decimal = Decimal.zero
    var remainingQuantity: Int = 0
    var lotTypeRaw: String = LotType.buy.rawValue

    init(
        id: UUID = UUID(),
        symbol: String,
        lotDate: Date,
        quantity: Int,
        pricePerShare: Decimal,
        totalFees: Decimal = Decimal.zero,
        lotType: LotType = .buy
    ) {
        self.id = id
        self.symbol = symbol
        self.lotDate = lotDate
        self.quantity = quantity
        self.pricePerShare = pricePerShare
        self.totalFees = totalFees
        self.lotTypeRaw = lotType.rawValue
        self.remainingQuantity = quantity
    }

    var lotType: LotType {
        get { LotType(rawValue: lotTypeRaw) ?? .buy }
        set { lotTypeRaw = newValue.rawValue }
    }

    var totalCost: Decimal {
        Decimal(quantity) * pricePerShare + totalFees
    }

    var remainingCost: Decimal {
        guard quantity > 0, remainingQuantity > 0 else { return Decimal.zero }
        return totalCost * Decimal(remainingQuantity) / Decimal(quantity)
    }

    var costPerShare: Decimal {
        guard quantity > 0 else { return Decimal.zero }
        return totalCost / Decimal(quantity)
    }

    var isAllocatableForSale: Bool {
        lotType == .buy && remainingQuantity > 0
    }
}
