import Foundation

enum AllocationValidationError: Error, Equatable {
    case unallocatedSharesRemaining(Int)
    case allocationExceedsSaleQuantity(by: Int)
    case lotHasInsufficientShares(lotDate: Date, available: Int, requested: Int)
    case nonPositiveQuantity(lotDate: Date)
    case stockAllocationLotNotAllowed(lotDate: Date)
    case symbolMismatch
}

struct DraftAllocation: Equatable {
    let lot: Lot
    var quantity: Int
}

enum AllocationValidator {
    static func validate(
        saleSymbol: String,
        saleQuantity: Int,
        lots: [Lot],
        drafts: [DraftAllocation]
    ) throws {
        guard saleQuantity > 0 else {
            throw AllocationValidationError.unallocatedSharesRemaining(0)
        }

        for draft in drafts where draft.quantity < 0 {
            throw AllocationValidationError.nonPositiveQuantity(lotDate: draft.lot.lotDate)
        }

        let combined = mergedByLot(drafts)

        for (lot, quantity) in combined {
            guard lot.symbol == saleSymbol else {
                throw AllocationValidationError.symbolMismatch
            }
            if lot.lotType == .stockAllocation {
                throw AllocationValidationError.stockAllocationLotNotAllowed(lotDate: lot.lotDate)
            }
            if quantity > lot.remainingQuantity {
                throw AllocationValidationError.lotHasInsufficientShares(
                    lotDate: lot.lotDate,
                    available: lot.remainingQuantity,
                    requested: quantity
                )
            }
        }

        let total = combined.values.reduce(0, +)
        if total < saleQuantity {
            throw AllocationValidationError.unallocatedSharesRemaining(saleQuantity - total)
        }
        if total > saleQuantity {
            throw AllocationValidationError.allocationExceedsSaleQuantity(by: total - saleQuantity)
        }
    }

    static func mergedByLot(_ drafts: [DraftAllocation]) -> [Lot: Int] {
        var merged: [UUID: (lot: Lot, quantity: Int)] = [:]
        var order: [UUID] = []
        for draft in drafts {
            if merged[draft.lot.id] == nil {
                order.append(draft.lot.id)
                merged[draft.lot.id] = (draft.lot, 0)
            }
            merged[draft.lot.id]?.quantity += draft.quantity
        }
        return order.reduce(into: [:]) { result, id in
            if let entry = merged[id] {
                result[entry.lot] = entry.quantity
            }
        }
    }

    static func message(for error: AllocationValidationError) -> String {
        switch error {
        case .unallocatedSharesRemaining(let shares):
            return "尚有 \(shares) 股未分配"
        case .allocationExceedsSaleQuantity(let by):
            return "分配股數超出賣出股數 \(by) 股"
        case .lotHasInsufficientShares(let lotDate, let available, let requested):
            return "\(Format.date(lotDate)) 批次僅剩 \(available) 股，無法分配 \(requested) 股"
        case .nonPositiveQuantity(let lotDate):
            return "\(Format.date(lotDate)) 批次的分配股數必須大於 0"
        case .stockAllocationLotNotAllowed(let lotDate):
            return "\(Format.date(lotDate)) 為配股批次，不可作為賣出配對"
        case .symbolMismatch:
            return "配對批次的股票代號與賣出代號不符"
        }
    }
}