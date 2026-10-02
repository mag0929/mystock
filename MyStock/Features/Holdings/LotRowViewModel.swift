import Foundation

struct LotRowViewModel: Identifiable {
    let id: UUID
    let lotDate: Date
    let quantityText: String
    let pricePerShareText: String
    let remainingText: String
    let typeText: String
    let costFieldsAvailable: Bool
    let commissionText: String
    let transactionTaxText: String

    init(lot: Lot) {
        id = lot.id
        lotDate = lot.lotDate
        quantityText = Format.decimal(Decimal(lot.quantity), fractionDigits: 0)
        remainingText = Format.decimal(Decimal(lot.remainingQuantity), fractionDigits: 0)
        let isAllocation = lot.lotType == .stockAllocation
        typeText = isAllocation ? "配股" : "買進"
        costFieldsAvailable = !isAllocation
        let fees = lot.feeBreakdown
        if isAllocation {
            pricePerShareText = "—"
            commissionText = "—"
            transactionTaxText = "—"
        } else {
            pricePerShareText = Format.decimal(lot.pricePerShare)
            commissionText = Format.money(fees.commission)
            transactionTaxText = Format.money(fees.transactionTax)
        }
    }
}

enum Format {
    static func decimal(_ value: Decimal, fractionDigits: Int = 2) -> String {
        var input = value
        var output = Decimal()
        NSDecimalRound(&output, &input, fractionDigits, .plain)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        formatter.usesGroupingSeparator = true
        return formatter.string(from: output as NSDecimalNumber) ?? "\(output)"
    }

    static func signedDecimal(_ value: Decimal, fractionDigits: Int = 0) -> String {
        let text = decimal(abs(value), fractionDigits: fractionDigits)
        return value < 0 ? "-\(text)" : "+\(text)"
    }

    static func percent(_ value: Decimal, fractionDigits: Int = 2) -> String {
        let scaled = value * 100
        let text = decimal(scaled, fractionDigits: fractionDigits)
        return value < 0 ? "\(text)%" : "+\(text)%"
    }

    /// Brokerage fees land on whole dollars, so showing "92.00" only adds noise.
    static func money(_ value: Decimal) -> String {
        var input = value
        var whole = Decimal()
        NSDecimalRound(&whole, &input, 0, .down)
        return whole == value ? decimal(whole, fractionDigits: 0) : decimal(value)
    }

    static func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: date)
    }
}
