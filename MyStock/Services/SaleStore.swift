import Foundation
import SwiftData

enum SaleStore {
    static func save(
        symbol: String,
        saleDate: Date,
        quantity: Int,
        pricePerShare: Decimal,
        drafts: [DraftAllocation],
        rates: FeeRates,
        in context: ModelContext
    ) throws -> Sale {
        let lots = drafts.map(\.lot)
        try AllocationValidator.validate(
            saleSymbol: symbol,
            saleQuantity: quantity,
            lots: lots,
            drafts: drafts
        )

        let gross = Decimal(quantity) * pricePerShare
        let sale = Sale(
            symbol: symbol,
            saleDate: saleDate,
            quantity: quantity,
            pricePerShare: pricePerShare,
            commission: FeeSettings.roundDownToWholeUnit(
                FeeSettings.commission(on: gross, rate: rates.commissionRate)
            ),
            transactionTax: FeeSettings.roundDownToWholeUnit(
                FeeSettings.transactionTax(on: gross, rate: rates.transactionTaxRate)
            ),
            securitiesTransactionTaxReference: FeeSettings.roundDownToWholeUnit(
                FeeSettings.securitiesTransactionTaxReference(on: gross)
            )
        )
        context.insert(sale)

        for (lot, allocated) in AllocationValidator.mergedByLot(drafts) {
            let allocation = SaleAllocation(sale: sale, lot: lot, quantity: allocated)
            context.insert(allocation)
            lot.remainingQuantity -= allocated
        }

        try context.save()
        return sale
    }

    static func allocations(for sale: Sale, in context: ModelContext) throws -> [SaleAllocation] {
        let saleID = sale.id
        let all = try context.fetch(FetchDescriptor<SaleAllocation>())
        return all
            .filter { $0.sale?.id == saleID }
            .sorted { ($0.lot?.lotDate ?? .distantPast) < ($1.lot?.lotDate ?? .distantPast) }
    }
}