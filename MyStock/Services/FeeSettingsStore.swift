import Foundation
import SwiftData

@Model
final class FeeSettingsRecord {
    var commissionRate: Decimal
    var transactionTaxRate: Decimal
    var updatedAt: Date

    init(
        commissionRate: Decimal = FeeSettings.defaultCommissionRate,
        transactionTaxRate: Decimal = FeeSettings.transactionTaxRate,
        updatedAt: Date = Date()
    ) {
        self.commissionRate = commissionRate
        self.transactionTaxRate = transactionTaxRate
        self.updatedAt = updatedAt
    }
}

struct FeeRates: Equatable {
    var commissionRate: Decimal
    var transactionTaxRate: Decimal
}

enum FeeSettingsStore {
    static func currentRates(in context: ModelContext) throws -> FeeRates {
        let descriptor = FetchDescriptor<FeeSettingsRecord>()
        if let record = try context.fetch(descriptor).first {
            return FeeRates(commissionRate: record.commissionRate, transactionTaxRate: record.transactionTaxRate)
        }
        return FeeRates(
            commissionRate: FeeSettings.defaultCommissionRate,
            transactionTaxRate: FeeSettings.transactionTaxRate
        )
    }

    static func update(
        commissionRate: Decimal,
        transactionTaxRate: Decimal,
        in context: ModelContext
    ) throws {
        let descriptor = FetchDescriptor<FeeSettingsRecord>()
        if let record = try context.fetch(descriptor).first {
            record.commissionRate = commissionRate
            record.transactionTaxRate = transactionTaxRate
            record.updatedAt = Date()
        } else {
            context.insert(
                FeeSettingsRecord(
                    commissionRate: commissionRate,
                    transactionTaxRate: transactionTaxRate
                )
            )
        }
        try context.save()
    }
}

enum LotFeeSnapshot {
    static func buyFees(
        quantity: Int,
        pricePerShare: Decimal,
        rates: FeeRates
    ) -> (commission: Decimal, transactionTax: Decimal, total: Decimal) {
        let gross = Decimal(quantity) * pricePerShare
        let commission = FeeSettings.commission(on: gross, rate: rates.commissionRate)
        let transactionTax = gross * rates.transactionTaxRate
        return (commission, transactionTax, commission + transactionTax)
    }

    static func makeBuyLot(
        symbol: String,
        lotDate: Date,
        quantity: Int,
        pricePerShare: Decimal,
        rates: FeeRates
    ) -> Lot {
        let fees = buyFees(quantity: quantity, pricePerShare: pricePerShare, rates: rates)
        return Lot(
            symbol: symbol,
            lotDate: lotDate,
            quantity: quantity,
            pricePerShare: pricePerShare,
            totalFees: fees.total,
            lotType: .buy
        )
    }
}