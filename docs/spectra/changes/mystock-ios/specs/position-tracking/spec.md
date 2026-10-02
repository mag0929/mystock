## Purpose

Position tracking records a user's Taiwan stock holdings as individual buy lots so that every purchase keeps its own cost, date, and fees. This capability is the data foundation for realized and unrealized profit calculations, and it must preserve the user's ability to decide which specific lot a sale is measured against.

## ADDED Requirements

### Requirement: Lot data model
The system SHALL represent every purchase as a separate lot. Each lot MUST record: lot identifier, stock symbol, lot date, quantity, price per share, total fees, remaining quantity, and lot type. Lot type SHALL be either `buy` or `stock-allocation`. The system SHALL compute the lot's remaining quantity as the purchased quantity minus the quantity already consumed by sales.

#### Scenario: Recording a purchase
- **WHEN** the user saves a new buy lot for symbol 2330 with quantity 1000, price per share 150, date 2026-01-10, and fees 1425
- **THEN** the system stores a lot with type `buy`, remaining quantity 1000, and total cost 151425

#### Scenario: Lot cost includes fees
- **WHEN** the system computes a lot's total cost
- **THEN** the system multiplies quantity by price per share and adds the recorded fees

##### Example: lot cost with and without fees
| Quantity | Price per share | Fees | Total cost |
| --- | --- | --- | --- |
| 1000 | 150 | 1425 | 151425 |
| 1000 | 90 | 1425 | 91425 |
| 200 | 109.09 | 0 | 21818 |

### Requirement: Stock symbol identity
The system SHALL identify each holding by Taiwan stock symbol as the primary grouping key. The system SHALL accept a symbol that the user has already created without requiring the user to re-enter the stock name, and the system SHALL allow the user to supply or correct the stock display name at any time.

#### Scenario: Grouping lots under one stock
- **WHEN** two lots exist for symbol 2330 with different lot dates
- **THEN** the system presents both lots under a single 2330 holding entry

### Requirement: Create, edit, and delete lots
The system SHALL allow the user to create, edit, and delete any lot. Deleting a lot SHALL also remove every sale allocation that references that lot, and the system SHALL recompute the affected holdings immediately after the deletion.

#### Scenario: Deleting a lot that has sale allocations
- **WHEN** the user deletes a lot that was previously consumed by a recorded sale
- **THEN** the system removes that lot's allocations from the sale and updates the holding's remaining quantity and unrealized profit figures

##### Example: deleting the lot a sale was allocated to
- **GIVEN** symbol 2330 has a lot of 1000 shares at 90 and a lot of 1000 shares at 150, and a sale of 1000 shares at 130 was allocated entirely to the lot at 90
- **WHEN** the user deletes the lot at 90
- **THEN** the sale has 0 shares allocated and is reported as incompletely allocated, and symbol 2330 reports 1000 remaining shares with total cost 150000

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
