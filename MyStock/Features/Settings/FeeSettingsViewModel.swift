import Foundation
import SwiftData

@MainActor
@Observable
final class FeeSettingsViewModel {
    var commissionRateText: String = ""
    var transactionTaxRateText: String = ""
    var statusMessage: String?
    var saveErrorMessage: String?

    private(set) var loadedRates: FeeRates?

    var commissionPercentText: String { percentText(for: commissionRateText) }
    var transactionTaxPercentText: String { percentText(for: transactionTaxRateText) }

    var canSave: Bool {
        Decimal(string: commissionRateText) != nil && Decimal(string: transactionTaxRateText) != nil
    }

    func load(context: ModelContext) {
        guard let rates = try? FeeSettingsStore.currentRates(in: context) else {
            saveErrorMessage = "無法讀取費率設定"
            return
        }
        loadedRates = rates
        commissionRateText = NSDecimalNumber(decimal: rates.commissionRate * 100).stringValue
        transactionTaxRateText = NSDecimalNumber(decimal: rates.transactionTaxRate * 100).stringValue
    }

    func save(context: ModelContext) {
        guard let commission = Decimal(string: commissionRateText),
              let tax = Decimal(string: transactionTaxRateText) else {
            saveErrorMessage = "請輸入有效的費率數值"
            return
        }
        do {
            try FeeSettingsStore.update(
                commissionRate: commission / 100,
                transactionTaxRate: tax / 100,
                in: context
            )
            statusMessage = "已儲存，僅影響之後建立的批次與賣出"
            saveErrorMessage = nil
            loadedRates = FeeRates(commissionRate: commission / 100, transactionTaxRate: tax / 100)
        } catch {
            saveErrorMessage = "儲存失敗：\(error.localizedDescription)"
        }
    }

    private func percentText(for text: String) -> String {
        guard let value = Decimal(string: text) else { return text }
        return Format.decimal(value, fractionDigits: 4) + "%"
    }
}