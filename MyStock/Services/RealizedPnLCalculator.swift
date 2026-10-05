import Foundation
import SwiftData

struct AllocationProfit: Equatable {
    let lotDate: Date
    let lotSymbol: String
    let quantity: Int
    let salePricePerShare: Decimal
    let lotCostPerShare: Decimal
    let grossResult: Decimal
    let allocatedDeductions: Decimal
    let realizedResult: Decimal
}

struct SaleResult: Equatable {
    let saleID: UUID
    let saleDate: Date
    let symbol: String
    let quantity: Int
    let pricePerShare: Decimal
    let commission: Decimal
    let transactionTax: Decimal
    let securitiesTransactionTaxReference: Decimal
    let allocations: [AllocationProfit]
    let totalDeductions: Decimal

    var realizedResult: Decimal {
        allocations.reduce(Decimal.zero) { $0 + $1.realizedResult }
    }

    /// What the shares sold for, before commission and transaction tax.
    var grossProceeds: Decimal {
        pricePerShare * Decimal(quantity)
    }

    /// The fee-inclusive cost of the allocated shares, which is the denominator
    /// the unrealized screen already uses for a return percentage, so the two
    /// screens stay comparable.
    var costBasis: Decimal {
        allocations.reduce(Decimal.zero) { $0 + $1.lotCostPerShare * Decimal($1.quantity) }
    }

    /// Nil when the cost basis is zero, so the screen can say why instead of
    /// printing a zero or an infinity that reads like a real return.
    var returnPercentage: Decimal? {
        guard costBasis > 0 else { return nil }
        return realizedResult / costBasis
    }

    var allocatedQuantity: Int {
        allocations.reduce(0) { $0 + $1.quantity }
    }

    /// Deleting a lot strips its allocations but leaves the sale in place, so a sale
    /// can end up with fewer shares accounted for than it recorded.
    var isCompleteAllocation: Bool {
        allocatedQuantity == quantity
    }
}

enum RealizedPnLCalculator {
    static func result(for sale: Sale, allocations: [SaleAllocation]) -> SaleResult {
        let entries = allocations
            .filter { $0.quantity > 0 }
            .sorted { ($0.lot?.lotDate ?? .distantPast) < ($1.lot?.lotDate ?? .distantPast) }
        let totalQuantity = entries.reduce(0) { $0 + $1.quantity }
        let totalDeductions = sale.totalDeductions

        var runningQuantity = 0
        let profits = entries.map { entry -> AllocationProfit in
            let lot = entry.lot
            let quantity = entry.quantity
            let gross = sale.pricePerShare * Decimal(quantity)
            let cost = (lot?.costPerShare ?? .zero) * Decimal(quantity)
            let deductions = allocatedShare(
                of: totalDeductions,
                quantity: quantity,
                totalAllocatedQuantity: totalQuantity,
                quantityAlreadyAllocated: runningQuantity,
                isLastAllocation: quantity + runningQuantity == totalQuantity
            )
            runningQuantity += quantity
            return AllocationProfit(
                lotDate: lot?.lotDate ?? Date(timeIntervalSince1970: 0),
                lotSymbol: lot?.symbol ?? "",
                quantity: quantity,
                salePricePerShare: sale.pricePerShare,
                lotCostPerShare: lot?.costPerShare ?? .zero,
                grossResult: gross,
                allocatedDeductions: deductions,
                realizedResult: gross - cost - deductions
            )
        }

        return SaleResult(
            saleID: sale.id,
            saleDate: sale.saleDate,
            symbol: sale.symbol,
            quantity: sale.quantity,
            pricePerShare: sale.pricePerShare,
            commission: sale.commission,
            transactionTax: sale.transactionTax,
            securitiesTransactionTaxReference: sale.securitiesTransactionTaxReference,
            allocations: profits,
            totalDeductions: totalDeductions
        )
    }

    static func results(
        for sales: [Sale],
        allocationsBySaleID: [UUID: [SaleAllocation]]
    ) -> [SaleResult] {
        sales
            .map { result(for: $0, allocations: allocationsBySaleID[$0.id] ?? []) }
            .sorted { $0.saleDate < $1.saleDate }
    }

    static func allocatedShare(
        of total: Decimal,
        quantity: Int,
        totalAllocatedQuantity: Int,
        quantityAlreadyAllocated: Int,
        isLastAllocation: Bool
    ) -> Decimal {
        guard totalAllocatedQuantity > 0, quantity > 0 else { return .zero }
        guard isLastAllocation else {
            return total * Decimal(quantity) / Decimal(totalAllocatedQuantity)
        }
        let assignedEarlier = total * Decimal(quantityAlreadyAllocated) / Decimal(totalAllocatedQuantity)
        return total - assignedEarlier
    }
}