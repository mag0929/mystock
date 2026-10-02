import Foundation
import SwiftData

@Model
final class Sale {
    var id: UUID = UUID()
    var symbol: String = ""
    var saleDate: Date = Date(timeIntervalSince1970: 0)
    var quantity: Int = 0
    var pricePerShare: Decimal = Decimal.zero
    var commission: Decimal = Decimal.zero
    var transactionTax: Decimal = Decimal.zero
    var securitiesTransactionTaxReference: Decimal = Decimal.zero

    init(
        id: UUID = UUID(),
        symbol: String,
        saleDate: Date,
        quantity: Int,
        pricePerShare: Decimal,
        commission: Decimal = Decimal.zero,
        transactionTax: Decimal = Decimal.zero,
        securitiesTransactionTaxReference: Decimal = Decimal.zero
    ) {
        self.id = id
        self.symbol = symbol
        self.saleDate = saleDate
        self.quantity = quantity
        self.pricePerShare = pricePerShare
        self.commission = commission
        self.transactionTax = transactionTax
        self.securitiesTransactionTaxReference = securitiesTransactionTaxReference
    }

    var grossProceeds: Decimal {
        Decimal(quantity) * pricePerShare
    }

    var totalDeductions: Decimal {
        commission + transactionTax
    }

    var netProceeds: Decimal {
        grossProceeds - totalDeductions
    }
}
