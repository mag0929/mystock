import Foundation

enum RealizedQueryPeriod: Equatable {
    case today
    case currentMonth
    case previousThreeMonths
    case custom(from: Date, to: Date)
}

struct RealizedQueryResult: Equatable {
    let period: RealizedQueryPeriod
    let sales: [SaleResult]
    let realizedTotal: Decimal
    let saleCount: Int
    let commissionTotal: Decimal
    let transactionTaxTotal: Decimal
    let securitiesTransactionTaxReferenceTotal: Decimal
    let bySymbol: [SymbolRealizedTotal]

    var totalDeductions: Decimal { commissionTotal + transactionTaxTotal }
}

struct SymbolRealizedTotal: Equatable {
    let symbol: String
    let realizedTotal: Decimal
    let saleCount: Int
    let quantitySold: Int
}

enum RealizedQueryCalendar {
    static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
        return calendar
    }

    static func interval(
        for period: RealizedQueryPeriod,
        now: Date,
        calendar: Calendar = RealizedQueryCalendar.calendar()
    ) -> DateInterval {
        let startOfToday = calendar.startOfDay(for: now)
        switch period {
        case .today:
            return DateInterval(start: startOfToday, duration: TimeInterval(86400))
        case .currentMonth:
            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? startOfToday
            let startOfNextMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) ?? now
            return DateInterval(start: startOfMonth, end: startOfNextMonth)
        case .previousThreeMonths:
            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? startOfToday
            let start = calendar.date(byAdding: .month, value: -3, to: startOfMonth) ?? startOfMonth
            let endOfCurrentMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth) ?? now
            return DateInterval(start: start, end: endOfCurrentMonth)
        case .custom(let from, let to):
            let start = calendar.startOfDay(for: from)
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: to)) ?? to
            return DateInterval(start: start, end: end)
        }
    }
}

enum RealizedQueryService {
    static func run(
        period: RealizedQueryPeriod,
        sales: [Sale],
        allocationsBySaleID: [UUID: [SaleAllocation]],
        now: Date = Date(),
        calendar: Calendar = RealizedQueryCalendar.calendar()
    ) -> RealizedQueryResult {
        let interval = RealizedQueryCalendar.interval(for: period, now: now, calendar: calendar)
        let matching = sales
            .filter { interval.contains($0.saleDate) }
            .sorted { $0.saleDate < $1.saleDate }

        let results = RealizedPnLCalculator.results(for: matching, allocationsBySaleID: allocationsBySaleID)
        let realizedTotal = results.reduce(Decimal.zero) { $0 + $1.realizedResult }

        var order: [String] = []
        var grouped: [String: [SaleResult]] = [:]
        for result in results {
            if grouped[result.symbol] == nil {
                order.append(result.symbol)
                grouped[result.symbol] = []
            }
            grouped[result.symbol]?.append(result)
        }
        let bySymbol = order.sorted().map { symbol in
            let entries = grouped[symbol] ?? []
            return SymbolRealizedTotal(
                symbol: symbol,
                realizedTotal: entries.reduce(Decimal.zero) { $0 + $1.realizedResult },
                saleCount: entries.count,
                quantitySold: entries.reduce(0) { $0 + $1.quantity }
            )
        }

        return RealizedQueryResult(
            period: period,
            sales: results,
            realizedTotal: realizedTotal,
            saleCount: results.count,
            commissionTotal: results.reduce(Decimal.zero) { $0 + $1.commission },
            transactionTaxTotal: results.reduce(Decimal.zero) { $0 + $1.transactionTax },
            securitiesTransactionTaxReferenceTotal: results.reduce(Decimal.zero) { $0 + $1.securitiesTransactionTaxReference },
            bySymbol: bySymbol
        )
    }
}