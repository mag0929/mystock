## Purpose

Unrealized profit reporting shows the user how the current market value of each holding compares to its cost, so the user can judge a position before selling it. This capability also supplies the market prices that the realized profit capability reuses when valuing a sale.

## ADDED Requirements

### Requirement: Quote retrieval
The system SHALL fetch a current price and a previous closing price for every stock symbol currently held. The primary source SHALL be the Yahoo Finance quote endpoint. When the primary source fails or returns no usable price for a symbol, the system SHALL fall back to the Taiwan Stock Exchange or Taipei Exchange public daily quote endpoint and use that closing price for both the current price and the previous closing price.

#### Scenario: Primary source succeeds
- **WHEN** the user opens the holdings screen and the Yahoo Finance endpoint returns a current price of 130 and a previous close of 125 for symbol 2330
- **THEN** the system uses 130 as the current price and 125 as the previous closing price for 2330

#### Scenario: Primary source fails
- **WHEN** the Yahoo Finance endpoint returns an error for symbol 2330 and the Taiwan Stock Exchange endpoint returns 128
- **THEN** the system uses 128 as both the current price and the previous closing price for 2330, and flags 2330 as using a closing-price fallback

#### Scenario: Both sources fail
- **WHEN** both the primary and fallback endpoints fail for symbol 2330
- **THEN** the system marks 2330 as having no available price, excludes 2330 from the current unrealized totals, and shows the failure on that holding's row

### Requirement: Quote refresh timing
The system SHALL fetch quotes when the holdings screen appears and when the user performs an explicit pull-to-refresh. The system SHALL NOT poll on a recurring timer. The system SHALL reuse the prices already held when computing profit figures and SHALL NOT require a new fetch for each calculation.

#### Scenario: Reopening the holdings screen
- **WHEN** the user navigates away from the holdings screen and returns to it within the same session
- **THEN** the system fetches quotes once for the reappearance and the displayed figures reflect that fetch

##### Example: fetch count across screen appearances
- **GIVEN** a fake HTTP client that counts requests, and symbol 2330 held with 2200 shares at total cost 240000
- **WHEN** the holdings screen appears, the user navigates away and returns, and the user then pulls to refresh
- **THEN** the fake client records exactly 3 quote requests, one per appearance and one for the pull-to-refresh, and no request is made while figures are recomputed from the already fetched price

### Requirement: Current price change percentage
The system SHALL compute current price change as the percentage difference between the current price and the previous closing price, and SHALL display it alongside the current price. When the previous closing price is zero, the system SHALL display the current price change as unavailable rather than as a percentage.

#### Scenario: Computing current price change
- **WHEN** symbol 2330 has a current price of 130 and a previous closing price of 125
- **THEN** the system displays a current price change of 4.00%

#### Scenario: Previous close is zero
- **WHEN** a symbol's previous closing price is 0
- **THEN** the system displays the current price change as unavailable

### Requirement: Single day gain or loss
The system SHALL compute single day gain or loss as the current price minus the previous closing price, multiplied by the holding's total remaining share count, and SHALL display the signed result per holding. When no price is available for the symbol, the system SHALL display single day gain or loss as unavailable.

#### Scenario: Computing single day result
- **WHEN** symbol 2330 has a current price of 130, a previous closing price of 125, and 2200 remaining shares
- **THEN** the system displays a single day gain of 11000

#### Scenario: Falling price
- **WHEN** symbol 2330 has a current price of 120, a previous closing price of 125, and 2200 remaining shares
- **THEN** the system displays a single day loss of 11000

### Requirement: Holding gain or loss against remaining cost
The system SHALL compute holding gain or loss as the current price multiplied by the holding's total remaining share count, minus the holding's total remaining cost, and SHALL display the signed result, the corresponding percentage, and the current price alongside it. The percentage SHALL be the holding gain or loss divided by the total remaining cost. When the total remaining cost is zero, the system SHALL display the percentage as unavailable and still display the absolute result. When no price is available, the system SHALL display the holding gain or loss as unavailable.

#### Scenario: Holding profit
- **WHEN** symbol 2330 has 2200 remaining shares, total remaining cost 240000, and a current price of 130
- **THEN** the system displays a holding gain of 46000 and a holding return of 19.17%

#### Scenario: Holding loss
- **WHEN** symbol 2330 has 2200 remaining shares, total remaining cost 240000, and a current price of 109.09
- **THEN** the system displays a holding loss of 2 and a holding return of 0.00%

##### Example: price equal to the rounded average cost
| Quantity | Total cost | Average cost per share | Current price | Holding result |
| --- | --- | --- | --- | --- |
| 2200 | 240000 | 109.09 | 109.09 | -2 |
| 2200 | 240000 | 109.090909… | 109.090909… | 0 |

The displayed average cost is rounded to two decimal places, so a current
price copied from the displayed average does not reproduce a zero result.
The system computes the result from the exact remaining cost and quantity,
not from the rounded average, so the second row is the only case that
returns 0.

#### Scenario: Zero remaining cost
- **WHEN** a holding's total remaining cost is 0 and a current price is available
- **THEN** the system displays the absolute holding result and displays the return percentage as unavailable

#### Scenario: No price available
- **WHEN** no price is available for a held symbol
- **THEN** the system displays current price change, single day result, and holding result as unavailable for that symbol

##### Example: one symbol priced, one not
- **GIVEN** symbol 2330 has 2200 shares at total cost 240000 with a current price of 130, and symbol 2317 has 1000 shares at total cost 50000 with no available price
- **WHEN** the system computes per-symbol and portfolio figures
- **THEN** 2330 shows a holding gain of 46000, 2317 shows all three figures as unavailable, and the portfolio holding gain is 46000 with a stated exclusion count of 1

### Requirement: Portfolio level unrealized totals
The system SHALL compute a portfolio-level holding gain or loss as the sum of the per-symbol holding results, and SHALL compute a portfolio-level single day result as the sum of the per-symbol single day results. Symbols without an available price SHALL be excluded from the totals, and the system SHALL display the number of excluded symbols when any are excluded.

#### Scenario: Summing across symbols
- **WHEN** symbol 2330 shows a holding gain of 46000 and symbol 2317 shows a holding loss of 5000, and both have available prices
- **THEN** the system displays a portfolio holding gain of 41000

#### Scenario: Excluding symbols without prices
- **WHEN** symbol 2330 shows a holding gain of 46000 and symbol 2317 has no available price
- **THEN** the system displays a portfolio holding gain of 46000 and states that 1 symbol is excluded

### Requirement: Fee-adjusted cost basis
The system SHALL include recorded lot fees and stock transaction tax in the holding cost basis so that the displayed holding result reflects net proceeds. The system SHALL read the applicable fee rates from a settings store, allowing the user to change the rates, and SHALL apply the rates in effect when the lot was recorded to that lot's stored cost.

#### Scenario: Fees included in holding cost
- **WHEN** symbol 2330 has a lot of 1000 shares at 150 with fees of 1425, and the current price is 130
- **THEN** the system computes the holding result from a cost basis of 151425, not 150000
