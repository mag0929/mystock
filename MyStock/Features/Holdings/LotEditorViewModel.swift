import Foundation
import SwiftData

@MainActor
@Observable
final class LotEditorViewModel {
    var symbol: String = ""
    var lotDate: Date = Date()
    var quantityText: String = ""
    var pricePerShareText: String = ""
    var isStockAllocation: Bool = false
    var errorMessage: String?
    var savedLotSymbol: String?

    private(set) var lot: Lot?

    func canSave(context: ModelContext) -> Bool {
        guard !symbol.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard let quantity = Int(quantityText), quantity > 0 else { return false }
        if isStockAllocation { return true }
        guard let price = Decimal(string: pricePerShareText), price > 0 else { return false }
        return true
    }

    func save(context: ModelContext) {
        let trimmedSymbol = symbol.trimmingCharacters(in: .whitespaces)
        guard !trimmedSymbol.isEmpty else {
            errorMessage = "請輸入股票代號"
            return
        }
        guard let quantity = Int(quantityText), quantity > 0 else {
            errorMessage = "股數必須是大於 0 的整數"
            return
        }
        if isStockAllocation {
            lot = Lot(
                symbol: trimmedSymbol,
                lotDate: lotDate,
                quantity: quantity,
                pricePerShare: 0,
                totalFees: 0,
                lotType: .stockAllocation
            )
        } else {
            guard let price = Decimal(string: pricePerShareText), price > 0 else {
                errorMessage = "單價必須大於 0"
                return
            }
            guard let rates = try? FeeSettingsStore.currentRates(in: context) else {
                errorMessage = "無法讀取費率設定"
                return
            }
            lot = LotFeeSnapshot.makeBuyLot(
                symbol: trimmedSymbol,
                lotDate: lotDate,
                quantity: quantity,
                pricePerShare: price,
                rates: rates
            )
        }
        guard let newLot = lot else { return }
        context.insert(newLot)
        do {
            try context.save()
            savedLotSymbol = trimmedSymbol
            errorMessage = nil
        } catch {
            errorMessage = "儲存失敗：\(error.localizedDescription)"
            context.delete(newLot)
            lot = nil
        }
    }
}