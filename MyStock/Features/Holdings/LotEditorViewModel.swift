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
    var displayName: String = ""
    var isResolvingName = false
    var nameLookupFailed = false

    private(set) var lot: Lot?

    private var editingLotID: UUID?
    private var resolvedSymbol: String?

    init(
        lot: Lot? = nil,
        directory: StockDirectory = StockDirectory()
    ) {
        self.directory = directory
        editingLotID = lot?.id
        if let lot {
            symbol = lot.symbol
            lotDate = lot.lotDate
            quantityText = String(lot.quantity)
            pricePerShareText = lot.lotType == .stockAllocation
                ? ""
                : Format.decimal(lot.pricePerShare)
            isStockAllocation = lot.lotType == .stockAllocation
        }
    }

    private let directory: StockDirectory

    /// Looks the symbol's name up so the user does not have to remember which
    /// company a four digit code belongs to. A name the user typed wins over the
    /// lookup, and a name already on file is used without asking the network.
    func resolveName(for typedSymbol: String, context: ModelContext) async {
        let trimmed = typedSymbol.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != resolvedSymbol else { return }
        resolvedSymbol = trimmed

        if let known = StockStore.name(for: trimmed, in: context) {
            displayName = known
            nameLookupFailed = false
            return
        }

        guard !ProcessInfo.processInfo.arguments.contains("-ui-testing") else {
            displayName = ""
            nameLookupFailed = true
            return
        }

        isResolvingName = true
        defer { isResolvingName = false }
        let resolved = await directory.name(for: trimmed)
        guard resolvedSymbol == trimmed else { return }
        nameLookupFailed = true
        if let name = resolved.name {
            displayName = name
            nameLookupFailed = false
            try? StockStore.upsertName(name, for: trimmed, in: context)
        } else {
            displayName = ""
        }
    }

    func updateName(_ name: String) {
        displayName = name.trimmingCharacters(in: .whitespaces)
    }

    var isEditing: Bool { editingLotID != nil }

    func existingLot(in context: ModelContext) -> Lot? {
        guard let editingLotID else { return nil }
        return try? context.fetch(FetchDescriptor<Lot>()).first { $0.id == editingLotID }
    }

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
        if let existing = existingLot(in: context) {
            saveEdit(of: existing, symbol: trimmedSymbol, quantity: quantity, in: context)
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
        if !displayName.isEmpty {
            try? StockStore.upsertName(displayName, for: trimmedSymbol, in: context)
        }
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

    private func saveEdit(of existing: Lot, symbol: String, quantity: Int, in context: ModelContext) {
        do {
            try LotStore.update(
                existing,
                symbol: symbol,
                lotDate: lotDate,
                quantity: quantity,
                pricePerShare: isStockAllocation ? 0 : (Decimal(string: pricePerShareText) ?? 0),
                lotType: isStockAllocation ? .stockAllocation : .buy,
                in: context
            )
            lot = existing
            savedLotSymbol = symbol
            errorMessage = nil
        } catch let error as LotEditError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "儲存失敗：\(error.localizedDescription)"
        }
    }
}