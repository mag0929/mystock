## Purpose

Position tracking records a user's Taiwan stock holdings as individual buy lots so that every purchase keeps its own cost, date, and fees. This capability is the data foundation for realized and unrealized profit calculations, and it must preserve the user's ability to decide which specific lot a sale is measured against.

## ADDED Requirements

### Requirement: Lot data model
The system SHALL represent every purchase as a separate lot. Each lot MUST record: lot identifier, stock symbol, lot date, quantity, price per share, total fees, remaining quantity, and lot type. Lot type SHALL be either `buy` or `stock-allocation`. The system SHALL compute the lot's remaining quantity as the purchased quantity minus the quantity already consumed by sales.

#### Scenario: Recording a purchase
- **WHEN** the user saves a new buy lot for symbol 2330 with quantity 1000, price per share 150, date 2026-01-10, and fees 1425
- **THEN** the system stores a lot with type `buy`, remaining quantity 1000, and total cost 151425

#### Scenario: A new buy lot's fees are commission only
- **WHEN** the system derives the fees for a new buy lot
- **THEN** the system records commission equal to the purchase value multiplied by the configured commission rate with the fraction discarded, and records no transaction tax, because Taiwan assesses the transaction tax and the securities transaction tax when shares are sold rather than bought

##### Example: fees on a purchase
| Symbol | Quantity | Price per share | Commission rate | Commission before truncation | Fees recorded |
| --- | --- | --- | --- | --- | --- |
| 8046 | 50 | 1300 | 0.1425% | 92.625 | 92 |
| 2330 | 1000 | 150 | 0.1425% | 213.75 | 213 |

##### Example: the sale tax rate does not reach a purchase
- **GIVEN** the transaction tax rate is 0.3 percent
- **WHEN** the user saves a buy lot for symbol 8046 with quantity 50 at 1300
- **THEN** the lot records fees of 92, not 287, and its total cost is 65092

#### Scenario: Commission and transaction tax are shown as separate figures
- **WHEN** the system displays a lot's fees
- **THEN** the system shows the commission and the transaction tax as two distinct amounts rather than a single combined total, and a lot recorded before this split shows its combined total as the commission

##### Example: reading a lot recorded before the split
- **GIVEN** a lot saved with a single combined fee of 1425 and no separate transaction tax
- **WHEN** the system reads that lot's fees
- **THEN** it reports a commission of 1425 and a transaction tax of 0

#### Scenario: Lot cost includes fees
- **WHEN** the system computes a lot's total cost
- **THEN** the system multiplies quantity by price per share and adds the recorded fees

##### Example: lot cost with and without fees
| Quantity | Price per share | Fees | Total cost |
| --- | --- | --- | --- |
| 1000 | 150 | 1425 | 151425 |
| 1000 | 90 | 1425 | 91425 |
| 200 | 109.09 | 0 | 21818 |

### Requirement: Stock name lookup from the symbol
The system SHALL treat a bare symbol as ambiguous and SHALL therefore resolve the company name when the user finishes entering a symbol, saving the result so later screens and later sessions show it without another lookup. The system SHALL prefer exchange sources, because they carry the Chinese short name, and SHALL treat a lookup failure as non-blocking.

#### Scenario: Entering a symbol brings up the name
- **WHEN** the user enters symbol 2330 in the lot form
- **THEN** the system resolves the name from the TWSE listing before saving, and the form shows the resolved name beside the symbol

##### Example: TWSE short name
- **GIVEN** the TWSE daily report for 2330 has title "115年06月 2330 台積電           各日成交資訊"
- **WHEN** the user enters symbol 2330
- **THEN** the form shows "台積電", not the English "TAIWAN SEMICONDUCTOR"

##### Example: a name already on file
- **GIVEN** symbol 2330 already has the stored name 台積電
- **WHEN** the user enters symbol 2330
- **THEN** the form shows 台積電 without any request to TWSE, TPEx, or Yahoo

##### Example: a user correction survives
- **GIVEN** the user corrected the stored name for 2330 to 台灣積體電路
- **WHEN** they enter 2330 again
- **THEN** the form still shows 台灣積體電路, not the exchange name 台積電

##### Example: an OTC code
- **GIVEN** the TWSE report for 6488 has no data, and the TPEx daily report has a row ["6488","環球晶","420.0"]
- **WHEN** the user enters symbol 6488
- **THEN** the form shows 環球晶

##### Example: correcting a wrong name
- **WHEN** the user replaces the resolved name with 聯電 before saving the lot
- **THEN** the lot saves with the name 聯電, and the holdings row for 2303 reads "2303 聯電"

#### Scenario: A lookup that finds nothing does not block saving
- **WHEN** every name source fails or returns nothing for the entered symbol
- **THEN** the form still allows saving the lot, and the holding is identified by its symbol alone

##### Example: several lots of one symbol
- **GIVEN** symbol 2330 already has the stored name 台積電, and the user later adds a second lot of 2330 and corrects the name to 台灣積體電路
- **WHEN** the second lot is saved
- **THEN** the app holds one stored name row for 2330, now reading 台灣積體電路

### Requirement: Displaying the name next to the symbol
The system SHALL show the saved name alongside the symbol wherever a symbol is presented as an identifier, so the user can tell which company a holding refers to.

#### Scenario: The holdings list identifies a holding by name
- **WHEN** symbol 2330 has a saved name of 台積電
- **THEN** the holdings summary row reads "2330 台積電" rather than a bare "2330"

#### Scenario: The sale symbol picker identifies a stock by name
- **WHEN** the sale form lists the symbols that have lots
- **THEN** each option reads "symbol name" when a name is stored, and falls back to the bare symbol when none is stored

#### Scenario: Realized profit groups and rows identify a stock by name
- **WHEN** the realized profit screen lists a symbol group or a single sale
- **THEN** each reads "symbol name" when a name is stored, and falls back to the bare symbol when none is stored

##### Example: a group heading with a name
- **GIVEN** symbol 2330 has the stored name 台積電
- **WHEN** the screen lists the realized profit group for 2330
- **THEN** the group heading reads "2330 台積電"

### Requirement: Stock symbol identity
The system SHALL identify each holding by Taiwan stock symbol as the primary grouping key. The system SHALL accept a symbol that the user has already created without requiring the user to re-enter the stock name, and the system SHALL allow the user to supply or correct the stock display name at any time.

#### Scenario: Grouping lots under one stock
- **WHEN** two lots exist for symbol 2330 with different lot dates
- **THEN** the system presents both lots under a single 2330 holding entry

### Requirement: Create, edit, and delete lots
The system SHALL allow the user to create, edit, and delete any lot. Deleting a lot SHALL also remove every sale allocation that references that lot, and the system SHALL recompute the affected holdings immediately after the deletion. Editing a lot SHALL NOT restate its fees, because the fee rate is snapshotted when the lot is created and later rate changes never apply backwards. Editing a lot's share count below the shares already sold from it SHALL be rejected rather than silently clamped.

#### Scenario: Editing a lot
- **WHEN** the user edits a lot's share count, price, and date
- **THEN** the system saves those figures to the same lot, keeps the shares already sold out of the remaining count, and keeps the fees recorded when the lot was created

##### Example: editing a partially sold lot
- **GIVEN** symbol 2330 has a lot of 1000 shares at 150, of which 400 were sold
- **WHEN** the user edits the lot to 800 shares
- **THEN** the lot records quantity 800 and remaining quantity 400

#### Scenario: Editing below the sold quantity
- **WHEN** the user edits a lot of 1000 shares down to 300 when 600 of them were already sold
- **THEN** the system rejects the change with an error naming the sold quantity, and the lot keeps quantity 1000 and remaining quantity 400

#### Scenario: Deleting a lot that has sale allocations
- **WHEN** the user deletes a lot that was previously consumed by a recorded sale
- **THEN** the system removes that lot's allocations from the sale and updates the holding's remaining quantity and unrealized profit figures

##### Example: deleting the lot a sale was allocated to
- **GIVEN** symbol 2330 has a lot of 1000 shares at 90 and a lot of 1000 shares at 150, and a sale of 1000 shares at 130 was allocated entirely to the lot at 90
- **WHEN** the user deletes the lot at 90
- **THEN** the sale has 0 shares allocated and is reported as incompletely allocated, and symbol 2330 reports 1000 remaining shares with total cost 150000

#### Scenario: The user can reach edit and delete from the holdings screen
- **WHEN** the user expands a holding and looks at one of its lots
- **THEN** the system lets the user open that lot for editing by tapping it, and offers a delete action by swiping it

##### Example: editing and deleting from the list
- **GIVEN** the holdings screen shows symbol 2330 with 2 lots
- **WHEN** the user expands the holding, taps a lot and saves a new share count, then swipes a lot and confirms the deletion
- **THEN** the edited lot shows the new share count and the deleted lot no longer appears in the list

### Requirement: Allocation lots for ex-rights stock dividends
The system SHALL provide a checkbox on the create-lot and edit-lot forms that marks the lot as a stock allocation. A lot marked as a stock allocation SHALL record the entered quantity as its remaining quantity, SHALL record a total cost of zero, SHALL be excluded from all fee calculations, and SHALL be included in the holding's total share count.

#### Scenario: Creating a stock allocation lot
- **WHEN** the user enables the stock allocation checkbox and saves a lot for symbol 2330 with quantity 200 and date 2026-04-01
- **THEN** the system stores a lot with type `stock-allocation`, remaining quantity 200, total cost 0, and zero fees

##### Example: stock allocation effect on a holding
- **GIVEN** symbol 2330 has two buy lots totalling 2000 shares with total cost 240000
- **WHEN** the user adds a stock allocation lot of 200 shares
- **THEN** the holding reports 2200 shares, total cost 240000, and average cost per share 109.09

### Requirement: Stock allocation lots are excluded from sale allocation candidates
The system SHALL NOT offer a lot with type `stock-allocation` as a candidate when the user allocates a sale. The candidate list SHALL contain only lots with type `buy` that still have remaining quantity greater than zero.

#### Scenario: Sale allocation list contents
- **WHEN** symbol 2330 holds two buy lots and one stock allocation lot
- **THEN** the sale allocation candidate list shows the two buy lots with remaining quantity and does not show the stock allocation lot

### Requirement: Per-lot display with type indicator
The system SHALL present holdings as a list of individual lots. Each lot row MUST display lot date, quantity, price per share, fees, remaining quantity, and lot type. A lot with type `stock-allocation` SHALL display its cost fields as unavailable rather than as zero, so that it is not read as missing data.

#### Scenario: Displaying a stock allocation lot
- **WHEN** the user expands a holding that contains a stock allocation lot
- **THEN** the lot row shows type `stock-allocation`, quantity 200, and cost fields shown as unavailable

### Requirement: Per-lot purchase figures against current value
The system SHALL show, on each lot row, the symbol and its company name alongside the figures that let the user judge that lot without consulting any other screen: the purchase side (lot date, type, remaining and original share counts, purchase price, buy commission, and remaining cost) and the current side (current price, market value of the remaining shares, unrealized gain or loss, and return percentage). A symbol and a date alone do not tell the user what they paid or what the position is now worth.

The lot's gain or loss SHALL be net of the commission and transaction tax that selling its remaining shares would incur, using the same definition the holding-level figure uses, so a lot row and its holding row report the same result for the same shares. It SHALL be computed from the lot's remaining shares and remaining cost, because shares already sold are reported as realized profit; a fully sold lot SHALL therefore report no unrealized result rather than counting its profit twice.

#### Scenario: A lot row shows the purchase figures next to the current figures
- **WHEN** the user expands a holding and a lot bought 200 shares at 141.5 with a buy commission of 40 has a current price of 152.5
- **THEN** the row shows symbol 2330 and its name, purchase price 141.50, commission 40, remaining cost 28340, current price 152.50, market value 30500, gain +2026, and return +7.15%

##### Example: three lots of the same symbol at the same current price
| Lot date | Quantity | Purchase price | Commission | Remaining cost | Market value | Gain | Return |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 2026/07/14 | 200 | 141.50 | 40 | 28340 | 30500 | +2026 | +7.15% |
| 2026/07/20 | 100 | 130.00 | 18 | 13018 | 15250 | +2166 | +16.64% |
| 2026/08/07 | 200 | 117.00 | 33 | 23433 | 30500 | +6933 | +29.59% |

Each gain is the market value less the remaining cost less the estimated sale
fees: 134, 66, and 134 respectively at a market value of 30500 and 15250.

#### Scenario: A partly sold lot is valued on the shares that remain
- **WHEN** a lot of 200 shares bought at 141.5 has had 100 shares sold and the current price is 152.5
- **THEN** the row shows a market value of 15250, a remaining cost of 14170, and a gain of 1014, rather than including the already realized half

#### Scenario: A fully sold lot reports no unrealized result
- **WHEN** every share of a lot has been sold
- **THEN** the row reports the unrealized gain and return as unavailable, because that profit has already moved to realized profit and reporting it again would count it twice

##### Example: a fully sold lot
- **GIVEN** a lot of 200 shares bought at 141.5 has had all 200 shares sold at 152.5
- **WHEN** the user expands the holding
- **THEN** the row still shows its purchase price 141.50 and commission 40, but its market value, gain, and return all read 不可用

#### Scenario: Without a price the current figures are unavailable
- **WHEN** no current price is available for a lot's symbol
- **THEN** the row reports the current price, market value, gain, and return as unavailable rather than as zero

##### Example: an unpriced symbol
- **GIVEN** a lot of 200 shares bought at 141.5 whose symbol has no available quote
- **WHEN** the user expands the holding
- **THEN** the row reads 持有成本 28,340 and 時價 不可用, 市價 不可用, 損益 不可用, 報酬率 不可用

### Requirement: Holding aggregates
The system SHALL compute, for each stock symbol, the total remaining quantity across all its lots, the total remaining cost across its lots, and the weighted average cost per share as total remaining cost divided by total remaining quantity. The system SHALL compute these aggregates over all lots of the symbol regardless of lot type.

#### Scenario: Aggregate across mixed lot types
- **WHEN** symbol 2330 has a buy lot of 2000 shares at total cost 240000 and a stock allocation lot of 200 shares
- **THEN** the holding reports 2200 shares, total cost 240000, and average cost per share 109.09

#### Scenario: All shares sold
- **WHEN** every lot of a symbol has remaining quantity zero
- **THEN** the system reports zero shares and excludes the symbol from the current holdings list while retaining the symbol's trade history

##### Example: fully sold symbol
- **GIVEN** symbol 2330 has a single lot of 1000 shares at 90 and a recorded sale of 1000 shares at 130
- **WHEN** the system computes the holding aggregates
- **THEN** symbol 2330 reports 0 remaining shares and does not appear in the current holdings list, while its sale remains listed in the realized profit query results

### Requirement: Local-only persistence
The system SHALL persist all lot data in on-device storage only. The system SHALL NOT require a user account and SHALL NOT transmit holdings data to any server. The system SHALL recreate all holdings, lots, and sale records from local storage on app launch.

#### Scenario: Relaunching the app
- **WHEN** the user force-quits the app and launches it again
- **THEN** all previously recorded lots and their remaining quantities are present with no network connection available

##### Example: restore after relaunch
- **GIVEN** symbol 2330 has a lot of 2000 shares at 150 with 500 shares already consumed by a recorded sale, so 1500 shares remain
- **WHEN** the app is relaunched and the holdings are read
- **THEN** symbol 2330 reports 1500 remaining shares and total cost 225000, matching the state before the relaunch
