import Foundation
import SwiftData

enum LotEditError: LocalizedError, Equatable {
    case quantityBelowSoldQuantity(quantity: Int, soldQuantity: Int)

    var errorDescription: String? {
        switch self {
        case let .quantityBelowSoldQuantity(quantity, soldQuantity):
            return "股數不能小於已賣出的 \(soldQuantity) 股，目前輸入 \(quantity) 股"
        }
    }
}

enum LotStore {
    static func allocations(for lot: Lot, in context: ModelContext) throws -> [SaleAllocation] {
        let lotID = lot.id
        let all = try context.fetch(FetchDescriptor<SaleAllocation>())
        return all.filter { $0.lot?.id == lotID }
    }

    static func soldQuantity(of lot: Lot) -> Int {
        max(0, lot.quantity - lot.remainingQuantity)
    }

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
        let soldQuantity = soldQuantity(of: lot)
        guard quantity >= soldQuantity else {
            throw LotEditError.quantityBelowSoldQuantity(
                quantity: quantity,
                soldQuantity: soldQuantity
            )
        }
        lot.symbol = symbol
        lot.lotDate = lotDate
        lot.quantity = quantity
        lot.pricePerShare = pricePerShare
        lot.totalFees = totalFees
        lot.lotType = lotType
        lot.remainingQuantity = quantity - soldQuantity
        try context.save()
    }
}
