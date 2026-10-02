import Foundation

enum FeeSettings {
    static let defaultCommissionRate = Decimal(string: "0.001425") ?? Decimal.zero
    static let transactionTaxRate = Decimal(string: "0.003") ?? Decimal.zero
    static let securitiesTransactionTaxRate = Decimal(string: "0.004") ?? Decimal.zero

    static func commission(on grossValue: Decimal, rate: Decimal) -> Decimal {
        grossValue * rate
    }

    static func transactionTax(on grossValue: Decimal, rate: Decimal) -> Decimal {
        grossValue * rate
    }

    static func transactionTax(on grossValue: Decimal) -> Decimal {
        transactionTax(on: grossValue, rate: transactionTaxRate)
    }

    static func securitiesTransactionTaxReference(on grossValue: Decimal) -> Decimal {
        grossValue * securitiesTransactionTaxRate
    }

    static func buyFees(
        quantity: Int,
        pricePerShare: Decimal,
        commissionRate: Decimal
    ) -> (commission: Decimal, transactionTax: Decimal) {
        let gross = Decimal(quantity) * pricePerShare
        return (commission(on: gross, rate: commissionRate), transactionTax(on: gross))
    }
}
