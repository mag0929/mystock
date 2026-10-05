import Foundation

/// The per-lot row the user asked for: the purchase figures next to what the
/// position is worth now, so a single row answers "am I up on this lot".
struct LotRowViewModel: Identifiable {
    let id: UUID
    let symbol: String
    let displayName: String?
    let lotDate: Date
    let quantityText: String
    let pricePerShareText: String
    let remainingText: String
    let typeText: String
    let costFieldsAvailable: Bool
    let commissionText: String
    let currentPriceText: String
    let remainingCostText: String
    let marketValueText: String
    let resultText: String
    let returnText: String
    let resultColorValue: Decimal?

    init(lot: Lot, displayName: String? = nil, metrics: LotMetrics? = nil) {
        id = lot.id
        symbol = lot.symbol
        self.displayName = displayName
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
        } else {
            pricePerShareText = Format.decimal(lot.pricePerShare)
            commissionText = Format.money(fees.commission)
        }

        if let metrics {
            currentPriceText = metrics.currentPrice.map { Format.decimal($0) } ?? "不可用"
            remainingCostText = Format.money(metrics.remainingCost)
            marketValueText = metrics.marketValue.map { Format.money($0) } ?? "不可用"
            resultText = metrics.result.map { Format.signedDecimal($0) } ?? "不可用"
            returnText = metrics.returnPercentage.map { Format.percent($0) } ?? "不可用"
            resultColorValue = metrics.result
        } else {
            currentPriceText = "不可用"
            remainingCostText = "不可用"
            marketValueText = "不可用"
            resultText = "不可用"
            returnText = "不可用"
            resultColorValue = nil
        }
    }
}

struct LotMetrics: Equatable {
    let currentPrice: Decimal?
    let marketValue: Decimal?
    let remainingCost: Decimal
    let estimatedSaleFees: Decimal
    let result: Decimal?
    let returnPercentage: Decimal?
}

enum LotPnLCalculator {
    /// Computed from the lot's remaining shares and remaining cost, because the
    /// shares already sold are reported as realized profit instead. A lot sold
    /// in full therefore reports no unrealized result rather than counting its
    /// profit twice.
    static func metrics(
        for lot: Lot,
        quote: Quote?,
        rates: FeeRates = FeeRates(
            commissionRate: FeeSettings.defaultCommissionRate,
            transactionTaxRate: FeeSettings.transactionTaxRate
        )
    ) -> LotMetrics {
        let remainingCost = lot.remainingCost
        guard let price = quote?.currentPrice, lot.remainingQuantity > 0 else {
            return LotMetrics(
                currentPrice: quote?.currentPrice,
                marketValue: nil,
                remainingCost: remainingCost,
                estimatedSaleFees: .zero,
                result: nil,
                returnPercentage: nil
            )
        }
        let marketValue = price * Decimal(lot.remainingQuantity)
        let fees = FeeSettings.estimatedSaleFees(
            quantity: lot.remainingQuantity,
            pricePerShare: price,
            rates: rates
        ).total
        let result = marketValue - remainingCost - fees
        return LotMetrics(
            currentPrice: price,
            marketValue: marketValue,
            remainingCost: remainingCost,
            estimatedSaleFees: fees,
            result: result,
            returnPercentage: remainingCost > 0 ? result / remainingCost : nil
        )
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