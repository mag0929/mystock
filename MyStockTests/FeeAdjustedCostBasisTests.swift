import Foundation
import SwiftData
import Testing
@testable import MyStock

@MainActor
@Suite("Fee-adjusted cost basis")
struct FeeAdjustedCostBasisTests {
    private func makeContext() throws -> ModelContext {
        let container = try Persistence.makeInMemoryContainer()
        return ModelContext(container)
    }

    @Test("Buying 50 shares of 8046 at 1300 costs 92 of fees")
    func buyCommissionOnlyFor8046() throws {
        let context = try makeContext()
        let rates = try FeeSettingsStore.currentRates(in: context)

        let fees = LotFeeSnapshot.buyFees(quantity: 50, pricePerShare: 1300, rates: rates)

        #expect(fees.commission == 92, "1300 × 50 × 0.001425 = 92.625，無條捨去為 92")
        #expect(fees.transactionTax == 0, "台股交易稅只在賣出時課徵，買進不計")
        #expect(fees.total == 92)
    }

    @Test("Buying 1000 shares at 150 costs commission only")
    func buyCarriesCommissionOnly() throws {
        let context = try makeContext()
        let rates = try FeeSettingsStore.currentRates(in: context)

        let fees = LotFeeSnapshot.buyFees(quantity: 1000, pricePerShare: 150, rates: rates)

        #expect(fees.commission == 213, "150000 × 0.001425 = 213.75，無條捨去為 213")
        #expect(fees.transactionTax == 0)
        #expect(fees.total == Decimal(213))
    }

    @Test("The buy commission does not move when only the transaction tax changes")
    func buyIgnoresTransactionTaxRate() throws {
        let before = FeeRates(
            commissionRate: Decimal(string: "0.001425") ?? .zero,
            transactionTaxRate: Decimal(string: "0.003") ?? .zero
        )
        let after = FeeRates(
            commissionRate: Decimal(string: "0.001425") ?? .zero,
            transactionTaxRate: Decimal(string: "0.005") ?? .zero
        )

        #expect(
            LotFeeSnapshot.buyFees(quantity: 50, pricePerShare: 1300, rates: before).total
                == LotFeeSnapshot.buyFees(quantity: 50, pricePerShare: 1300, rates: after).total
        )
    }

    @Test("The commission fraction is discarded rather than rounded up")
    func commissionTruncatesRatherThanRounds() throws {
        #expect(FeeSettings.roundDownToWholeUnit(Decimal(string: "92.625")!) == 92)
        #expect(FeeSettings.roundDownToWholeUnit(Decimal(string: "92.999")!) == 92)
        #expect(FeeSettings.roundDownToWholeUnit(Decimal(string: "92.001")!) == 92)
        #expect(FeeSettings.roundDownToWholeUnit(93) == 93)
    }

    @Test("Fees included in holding cost")
    func feesIncludedInHoldingCost() throws {
        let rates = FeeRates(
            commissionRate: Decimal(string: "0.00095") ?? .zero,
            transactionTaxRate: Decimal(string: "0.003") ?? .zero
        )
        let lot = LotFeeSnapshot.makeBuyLot(
            symbol: "2330",
            lotDate: Fixtures.makeDate(2026, 1, 10),
            quantity: 1000,
            pricePerShare: 150,
            rates: rates
        )

        #expect(lot.totalFees == Decimal(142), "150000 × 0.00095 = 142.5，無條捨去為 142")
        #expect(lot.totalCost == Decimal(150142))
    }

    @Test("Cost basis of 151425 from 1425 of fees")
    func costBasisOf151425() {
        let lot = Lot(
            symbol: "2330",
            lotDate: Fixtures.makeDate(2026, 1, 10),
            quantity: 1000,
            pricePerShare: 150,
            totalFees: 1425
        )
        let holding = HoldingCalculator.holdings(from: [lot])[0]

        #expect(holding.totalRemainingCost == 151425)
        #expect(holding.totalRemainingCost != 150000)
    }

    @Test("Changing the rate does not retroactively change existing lots")
    func changingRateDoesNotAffectExistingLots() throws {
        let context = try makeContext()
        let originalRates = try FeeSettingsStore.currentRates(in: context)
        let existing = LotFeeSnapshot.makeBuyLot(
            symbol: "2330",
            lotDate: Fixtures.makeDate(2026, 1, 10),
            quantity: 1000,
            pricePerShare: 150,
            rates: originalRates
        )
        context.insert(existing)
        try context.save()
        let costBefore = existing.totalCost

        try FeeSettingsStore.update(
            commissionRate: Decimal(string: "0.0015") ?? .zero,
            transactionTaxRate: Decimal(string: "0.003") ?? .zero,
            in: context
        )
        let newRates = try FeeSettingsStore.currentRates(in: context)
        let createdAfter = LotFeeSnapshot.makeBuyLot(
            symbol: "2330",
            lotDate: Fixtures.makeDate(2026, 6, 1),
            quantity: 1000,
            pricePerShare: 150,
            rates: newRates
        )

        #expect(existing.totalCost == costBefore)
        #expect(createdAfter.totalFees != existing.totalFees)
        #expect(newRates.commissionRate == Decimal(string: "0.0015"))
    }

    @Test("Rates persist across a fresh context")
    func ratesPersistAcrossContext() throws {
        let container = try Persistence.makeInMemoryContainer()
        let writer = ModelContext(container)
        try FeeSettingsStore.update(
            commissionRate: Decimal(string: "0.001") ?? .zero,
            transactionTaxRate: Decimal(string: "0.0025") ?? .zero,
            in: writer
        )

        let reader = ModelContext(container)
        let rates = try FeeSettingsStore.currentRates(in: reader)

        #expect(rates.commissionRate == Decimal(string: "0.001"))
        #expect(rates.transactionTaxRate == Decimal(string: "0.0025"))
    }

    @Test("A stock allocation lot carries no fees")
    func stockAllocationCarriesNoFees() {
        let lot = Lot(
            symbol: "2330",
            lotDate: Fixtures.makeDate(2026, 4, 1),
            quantity: 200,
            pricePerShare: 0,
            totalFees: 0,
            lotType: .stockAllocation
        )
        #expect(lot.totalCost == 0)
        #expect(lot.totalFees == 0)
    }
}