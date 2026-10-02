import Foundation
import SwiftData

@MainActor
@Observable
final class SaleEditorViewModel {
    var selectedSymbol: String = ""
    var saleDate: Date = Date()
    var quantityText: String = ""
    var pricePerShareText: String = ""
    var allocations: [UUID: String] = [:]
    var errorMessage: String?
    var savedSaleID: UUID?
    private(set) var allocationSummary: [AllocationProfit] = []

    private(set) var candidates: [Lot] = []

    var totalAllocationResult: Decimal {
        allocationSummary.reduce(Decimal.zero) { $0 + $1.realizedResult }
    }

    func loadCandidates(from lots: [Lot]) {
        candidates = HoldingCalculator.saleAllocationCandidates(from: lots, symbol: selectedSymbol)
        allocations = [:]
    }

    var symbols: [String] {
        Array(Set(candidates.map(\.symbol))).sorted()
    }

    var allocatedQuantity: Int {
        drafts.reduce(0) { $0 + $1.quantity }
    }

    var unallocatedQuantity: Int {
        (Int(quantityText) ?? 0) - allocatedQuantity
    }

    var drafts: [DraftAllocation] {
        candidates.compactMap { lot in
            guard let text = allocations[lot.id], let quantity = Int(text), quantity > 0 else { return nil }
            return DraftAllocation(lot: lot, quantity: quantity)
        }
    }

    func canSave(context: ModelContext) -> Bool {
        guard !selectedSymbol.isEmpty else { return false }
        guard let quantity = Int(quantityText), quantity > 0 else { return false }
        guard let price = Decimal(string: pricePerShareText), price > 0 else { return false }
        guard allocatedQuantity == quantity else { return false }
        return true
    }

    func save(context: ModelContext) {
        guard !selectedSymbol.isEmpty else {
            errorMessage = "請選擇股票代號"
            return
        }
        guard let quantity = Int(quantityText), quantity > 0 else {
            errorMessage = "賣出股數必須是大於 0 的整數"
            return
        }
        guard let price = Decimal(string: pricePerShareText), price > 0 else {
            errorMessage = "賣價必須大於 0"
            return
        }
        guard let rates = try? FeeSettingsStore.currentRates(in: context) else {
            errorMessage = "無法讀取費率設定"
            return
        }
        do {
            let sale = try SaleStore.save(
                symbol: selectedSymbol,
                saleDate: saleDate,
                quantity: quantity,
                pricePerShare: price,
                drafts: drafts,
                rates: rates,
                in: context
            )
            savedSaleID = sale.id
            errorMessage = nil
        } catch let error as AllocationValidationError {
            errorMessage = AllocationValidator.message(for: error)
        } catch {
            errorMessage = "儲存失敗：\(error.localizedDescription)"
        }
    }

    func recalculate(context: ModelContext) {
        allocationSummary = allocationSummary(context: context).map(\.result)
    }

    func allocationSummary(context: ModelContext) -> [(lot: Lot, result: AllocationProfit)] {
        let quantity = Int(quantityText) ?? 0
        let price = Decimal(string: pricePerShareText) ?? .zero
        let allocations = drafts
        let gross = Decimal(quantity) * price
        let rates = (try? FeeSettingsStore.currentRates(in: context))
            ?? FeeRates(commissionRate: FeeSettings.defaultCommissionRate, transactionTaxRate: FeeSettings.transactionTaxRate)
        let commission = FeeSettings.commission(on: gross, rate: rates.commissionRate)
        let tax = FeeSettings.transactionTax(on: gross, rate: rates.transactionTaxRate)
        let totalDeductions = commission + tax
        let totalQuantity = allocations.reduce(0) { $0 + $1.quantity }

        var running = 0
        return allocations.map { draft in
            let lot = draft.lot
            let share = RealizedPnLCalculator.allocatedShare(
                of: totalDeductions,
                quantity: draft.quantity,
                totalAllocatedQuantity: totalQuantity,
                quantityAlreadyAllocated: running,
                isLastAllocation: running + draft.quantity == totalQuantity
            )
            running += draft.quantity
            let profit = AllocationProfit(
                lotDate: lot.lotDate,
                lotSymbol: lot.symbol,
                quantity: draft.quantity,
                salePricePerShare: price,
                lotCostPerShare: lot.costPerShare,
                grossResult: price * Decimal(draft.quantity),
                allocatedDeductions: share,
                realizedResult: price * Decimal(draft.quantity) - lot.costPerShare * Decimal(draft.quantity) - share
            )
            return (lot, profit)
        }
    }
}