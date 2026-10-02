import Foundation
import SwiftData

/// The two fees Taiwan charges, kept apart so the user can see what each one is.
struct LotFeeBreakdown: Equatable {
    let commission: Decimal
    let transactionTax: Decimal
}

@Model
final class Lot {
    var id: UUID = UUID()
    var symbol: String = ""
    var lotDate: Date = Date(timeIntervalSince1970: 0)
    var quantity: Int = 0
    var pricePerShare: Decimal = Decimal.zero
    var totalFees: Decimal = Decimal.zero
    var commission: Decimal = Decimal.zero
    var transactionTax: Decimal = Decimal.zero
    var remainingQuantity: Int = 0
    var lotTypeRaw: String = LotType.buy.rawValue

    init(
        id: UUID = UUID(),
        symbol: String,
        lotDate: Date,
        quantity: Int,
        pricePerShare: Decimal,
        totalFees: Decimal = Decimal.zero,
        commission: Decimal? = nil,
        transactionTax: Decimal = Decimal.zero,
        lotType: LotType = .buy
    ) {
        self.id = id
        self.symbol = symbol
        self.lotDate = lotDate
        self.quantity = quantity
        self.pricePerShare = pricePerShare
        self.transactionTax = transactionTax
        self.lotTypeRaw = lotType.rawValue
        self.remainingQuantity = quantity
        // Lots saved before the fees were broken out carry only the combined figure.
        if let commission {
            self.commission = commission
            self.totalFees = commission + transactionTax
        } else {
            self.commission = totalFees
            self.totalFees = totalFees
        }
    }

    var lotType: LotType {
        get { LotType(rawValue: lotTypeRaw) ?? .buy }
        set { lotTypeRaw = newValue.rawValue }
    }

    /// A lot recorded before the split has no commission field, so the combined
    /// total it does have is read back as commission.
    var feeBreakdown: LotFeeBreakdown {
        if commission == 0, transactionTax == 0, totalFees != 0 {
            return LotFeeBreakdown(commission: totalFees, transactionTax: 0)
        }
        return LotFeeBreakdown(commission: commission, transactionTax: transactionTax)
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
