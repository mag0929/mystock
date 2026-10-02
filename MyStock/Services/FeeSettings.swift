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

    /// Taiwan assesses the transaction tax and the securities transaction tax when
    /// shares are sold, not when they are bought, so a purchase carries commission only.
    static func buyCommission(
        quantity: Int,
        pricePerShare: Decimal,
        rate: Decimal
    ) -> Decimal {
        roundDownToWholeUnit(commission(on: Decimal(quantity) * pricePerShare, rate: rate))
    }

    /// Brokerages charge commission in whole dollars, discarding the fraction rather
    /// than rounding it up.
    static func roundDownToWholeUnit(_ value: Decimal) -> Decimal {
        var input = value
        var output = Decimal()
        NSDecimalRound(&output, &input, 0, .down)
        return output
    }
}
