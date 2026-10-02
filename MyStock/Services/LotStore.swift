import Foundation
import SwiftData

enum LotStore {
    static func delete(_ lot: Lot, in context: ModelContext) throws {
        let lotID = lot.id
        let allocations = try context.fetch(FetchDescriptor<SaleAllocation>())
        for allocation in allocations where allocation.lot?.id == lotID {
            context.delete(allocation)
        }
        context.delete(lot)
        try context.save()
    }

    static func update(
        _ lot: Lot,
        symbol: String,
        lotDate: Date,
        quantity: Int,
        pricePerShare: Decimal,
        totalFees: Decimal,
        lotType: LotType,
        in context: ModelContext
    ) throws {
        let soldQuantity = lot.quantity - lot.remainingQuantity
        lot.symbol = symbol
        lot.lotDate = lotDate
        lot.quantity = quantity
        lot.pricePerShare = pricePerShare
        lot.totalFees = totalFees
        lot.lotType = lotType
        lot.remainingQuantity = max(0, quantity - soldQuantity)
        try context.save()
    }
}
