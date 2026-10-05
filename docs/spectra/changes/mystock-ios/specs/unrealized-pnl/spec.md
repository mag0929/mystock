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

### Requirement: Holding gain or loss is net of the fees a sale would incur
The system SHALL compute holding gain or loss as the current price multiplied by the holding's total remaining share count, minus the holding's total remaining cost, minus the commission and transaction tax that selling those shares now would incur. It SHALL display the signed result, the corresponding percentage, and the current price alongside it. The percentage SHALL be the holding gain or loss divided by the total remaining cost.

The estimated sale fees SHALL be computed at the rates currently configured in the settings store and SHALL be truncated to whole dollars exactly as a recorded sale truncates them, so the estimate does not promise a fraction of a dollar that a brokerage would not return. Deducting the fees is required because a gross figure reads as more profit than the user would actually receive, and the same figure is reported once realized in the realized profit screens.

When the total remaining cost is zero, the system SHALL display the percentage as unavailable and still display the absolute result. When no price is available, the system SHALL display the holding gain or loss as unavailable.

#### Scenario: The figures state that the fees are already deducted
- **WHEN** the user views a holding or the portfolio total
- **THEN** the screen states that 持有收益 and the per-lot 損益 are already net of the estimated sale commission and transaction tax, so a gross gain is never what the user reads

##### Example: the note on both screens
- **GIVEN** a holding of 2200 shares with cost 240000 at a current price of 130
- **WHEN** the user reads the holding row and the portfolio total
- **THEN** both places carry the text 持有收益與批次損益已依設定費率扣除估計賣出手續費與交易稅, next to the 44735 figure

#### Scenario: Holding profit is net of the estimated sale fees
- **WHEN** symbol 2330 has 2200 remaining shares, total remaining cost 240000, and a current price of 130
- **THEN** the system displays a holding gain of 44735 and a holding return of 18.64%, being 286000 market value less 240000 cost less 1265 estimated sale fees

##### Example: the estimated fees at a market value of 286000
| Component | Rate | Before truncation | Recorded |
| --- | --- | --- | --- |
| Commission | 0.1425% | 407.55 | 407 |
| Transaction tax | 0.3% | 858 | 858 |
| Total deducted | | | 1265 |

#### Scenario: Selling at the average cost still loses the fees
- **WHEN** symbol 2330 has 2200 remaining shares, total remaining cost 240000, and a current price equal to the average cost
- **THEN** the system displays a holding loss of 1062 and a holding return of -0.44%, because the fees would still be paid at a break-even price

##### Example: break-even price still shows a loss
| Quantity | Total cost | Current price | Holding result |
| --- | --- | --- | --- |
| 2200 | 240000 | 109.09 | -1062 |
| 2200 | 240000 | 109.090909… | -1060 |

Reporting 0 at a break-even price would promise a profit the user would not receive.
The difference between the two rows is the truncated commission on a slightly
different market value, not rounding of the displayed average cost.

#### Scenario: Average cost and current price shown together
- **WHEN** symbol 2330 has 2200 remaining shares, total remaining cost 240000, and a current price of 130
- **THEN** the system displays the average cost 109.09 alongside the current price 130 on the same holding row

#### Scenario: No shares held
- **WHEN** a holding has no remaining shares
- **THEN** the system displays the average cost as unavailable rather than as zero

##### Example: a fully sold holding
- **GIVEN** symbol 2330 bought 1000 shares at 130 and later sold all 1000, leaving 0 remaining shares
- **WHEN** the system computes the holding's average cost
- **THEN** the system reports the average cost as unavailable, because dividing the remaining cost by a zero share count has no value

#### Scenario: Zero remaining cost
- **WHEN** a holding's total remaining cost is 0 and a current price is available
- **THEN** the system displays the absolute holding result and displays the return percentage as unavailable

#### Scenario: No price available
- **WHEN** no price is available for a held symbol
- **THEN** the system displays current price change, single day result, and holding result as unavailable for that symbol

##### Example: one symbol priced, one not
- **GIVEN** symbol 2330 has 2200 shares at total cost 240000 with a current price of 130, and symbol 2317 has 1000 shares at total cost 50000 with no available price
- **WHEN** the system computes per-symbol and portfolio figures
- **THEN** 2330 shows a holding gain of 44735, 2317 shows all three figures as unavailable, and the portfolio holding gain is 44735 with a stated exclusion count of 1

### Requirement: Portfolio level unrealized totals
The system SHALL compute a portfolio-level holding gain or loss as the sum of the per-symbol holding results, and SHALL compute a portfolio-level single day result as the sum of the per-symbol single day results. Symbols without an available price SHALL be excluded from the totals, and the system SHALL display the number of excluded symbols when any are excluded.

#### Scenario: Summing across symbols
- **WHEN** symbol 2330 shows a holding gain of 44735 and symbol 2317 shows a holding loss of 5199, and both have available prices
- **THEN** the system displays a portfolio holding gain of 39536

#### Scenario: Excluding symbols without prices
- **WHEN** symbol 2330 shows a holding gain of 44735 and symbol 2317 has no available price
- **THEN** the system displays a portfolio holding gain of 44735 and states that 1 symbol is excluded

### Requirement: Fee-adjusted cost basis
The system SHALL include recorded lot fees and stock transaction tax in the holding cost basis so that the displayed holding result reflects net proceeds. The system SHALL read the applicable fee rates from a settings store, allowing the user to change the rates, and SHALL apply the rates in effect when the lot was recorded to that lot's stored cost.

#### Scenario: Fees included in holding cost
- **WHEN** symbol 2330 has a lot of 1000 shares at 150 with fees of 1425, and the current price is 130
- **THEN** the system computes the holding result from a cost basis of 151425, not 150000
