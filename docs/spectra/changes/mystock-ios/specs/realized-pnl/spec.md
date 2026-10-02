## Purpose

Realized profit reporting records sales against the specific purchase lots the user designates, so that the profit recognized on a sale matches the user's own trading intent rather than a fixed cost algorithm. This capability exists because fixed algorithms misattribute a deliberate loss-cutting sale as a gain and inflate the taxable realized gain that Taiwan's securities transaction tax applies to.

## ADDED Requirements

### Requirement: Sale record with user-designated lot allocation
The system SHALL require the user to designate, for every recorded sale, which buy lots the sale is measured against and how many shares of each lot the sale consumes. The system SHALL provide no default allocation and SHALL NOT complete a sale without an explicit allocation for every share sold. The system SHALL support allocating one sale across multiple buy lots.

#### Scenario: Allocating a sale to a single lot
- **WHEN** the user records a sale of 1000 shares of 2330 at 130 on 2026-03-05 and allocates all 1000 shares to the lot bought on 2026-02-20 at 90
- **THEN** the system stores the sale with 1000 shares allocated to that lot and 0 shares allocated to any other lot

#### Scenario: Allocating a sale across multiple lots
- **WHEN** the user records a sale of 1000 shares of 2330 at 130 and allocates 400 shares to the lot bought at 90 and 600 shares to the lot bought at 150
- **THEN** the system stores both allocations and the sale's total allocated shares equal 1000

#### Scenario: Unallocated shares are rejected
- **WHEN** the user records a sale of 1000 shares but allocates only 900 shares in total
- **THEN** the system refuses to save the sale and reports that 100 shares remain unallocated

### Requirement: Allocation integrity constraints
The system SHALL enforce two constraints when saving a sale: the sum of allocated shares across all lots MUST equal the sale quantity, and no lot's remaining quantity SHALL become negative. The system MUST reject a save that would violate either constraint and SHALL state which constraint was violated.

#### Scenario: Allocated quantity mismatch
- **WHEN** the user records a sale of 1000 shares and allocates 1100 shares in total
- **THEN** the system refuses to save the sale and reports that the allocation exceeds the sale quantity by 100 shares

#### Scenario: Allocation exceeds a lot's remaining shares
- **WHEN** a lot has 500 remaining shares and the user allocates 600 shares of a sale to that lot
- **THEN** the system refuses to save the sale and reports that the lot has only 500 shares available

#### Scenario: Duplicate allocation to the same lot
- **WHEN** the user records allocations of 400 and 300 shares to the same lot that has 500 remaining shares
- **THEN** the system treats the two entries as a combined 700 shares and refuses to save the sale because the combined amount exceeds the lot's remaining shares

### Requirement: Realized profit per allocated lot
The system SHALL compute the realized profit of each sale-lot allocation as the sale price multiplied by the allocated shares, minus the lot's per-share cost multiplied by the allocated shares, minus the sale's share of fees and transaction tax. The system's realized profit for a sale MUST equal the sum of its allocations' realized profits.

#### Scenario: Realized profit on a single allocation
- **WHEN** a sale of 1000 shares at 130 is allocated entirely to a lot of 1000 shares bought at 90 with total fees 1425
- **THEN** the system reports realized profit of 40000 minus the sale's fees and transaction tax

##### Example: allocation choice changes the reported split
- **GIVEN** symbol 2330 has a lot of 1000 shares at 150 and a lot of 1000 shares at 90
- **WHEN** 1000 shares are sold at 130 and allocated to the lot bought at 90
- **THEN** realized profit is +40000, remaining cost is 150000, and the unrealized result at 130 is -20000
- **WHEN** 1000 shares are sold at 130 and allocated to the lot bought at 150
- **THEN** realized profit is -20000, remaining cost is 90000, and the unrealized result at 130 is +40000

### Requirement: Total profit conservation
For each symbol, the system SHALL satisfy the identity below, where every term is stated in the same units:

`realized profit + sale deductions + unrealized result = remaining market value + sale proceeds − acquisition cost`

Here acquisition cost includes the fees recorded on each buy lot, sale proceeds are gross of fees, sale deductions are the fees and transaction tax of the sales, remaining market value is the remaining cost basis plus the current unrealized result, and unrealized result is the remaining cost basis plus its market gain or loss. The system's allocation mechanism MUST NOT change the right-hand side or the total on the left.

The remaining market value term is required because a sale removes shares without removing their cost basis: the cost basis stays on the left as unrealized result, so the proceeds have to be offset against it for the identity to close.

#### Scenario: Total is independent of allocation
- **GIVEN** symbol 2330 has a lot of 1000 shares at 150 and a lot of 1000 shares at 90, with no fees
- **WHEN** 1000 shares are sold at 130
- **THEN** realized profit plus sale deductions plus unrealized result equals 20000 regardless of which lot the sale was allocated to

#### Scenario: Identity includes the remaining market value
- **GIVEN** the same two lots and the same sale as the scenario above
- **WHEN** the system computes both sides of the identity
- **THEN** the remaining market value of 1000 remaining shares at 130, plus sale proceeds of 130000, equals the acquisition cost of 240000 plus the left-hand total of 20000

##### Example: the identity evaluated on both sides

- **GIVEN** two lots of 1000 shares at 150 and at 90 with no fees, and a
  current price of 130
- **WHEN** 1000 shares are sold at 130 and allocated entirely to the lot at 90
- **THEN** both sides of the identity equal 20000

| Term | Value |
| --- | --- |
| Realized profit, net of sale deductions | +39425 |
| Sale deductions | 575 |
| Unrealized result on the 1000 remaining shares, cost basis 150000 at 130 | −20000 |
| Left side: realized plus deductions plus unrealized | 20000 |
| Remaining market value, 1000 shares at 130 | 130000 |
| Sale proceeds, 1000 shares at 130 | 130000 |
| Acquisition cost, both lots | 240000 |
| Right side: remaining market value plus proceeds − acquisition cost | 20000 |

Omit the sale deductions row and the left side reads 19425 while the
right side stays 20000, which is why the deductions term appears in the
identity rather than being folded into the realized profit.

### Requirement: Stock allocation lots are never allocated
The system SHALL reject any attempt to allocate a sale to a lot of type `stock-allocation`. When a user attempts this, the system SHALL report that the lot is a stock allocation lot and cannot be used for sale allocation.

#### Scenario: Rejecting a stock allocation as an allocation target
- **WHEN** the user attempts to allocate shares of a sale to a stock allocation lot
- **THEN** the system refuses the allocation and reports that stock allocation lots cannot be allocated to sales

##### Example: stock allocation is not offered and is rejected if forced
- **GIVEN** symbol 2330 has a buy lot of 2000 shares at 150 and a stock allocation lot of 200 shares
- **WHEN** the user records a sale of 200 shares and attempts to allocate all 200 shares to the stock allocation lot
- **THEN** the system refuses the allocation and reports that the stock allocation lot of 200 shares dated 2026-04-01 cannot be allocated, while the buy lot remains available for allocation

### Requirement: Realized profit query periods
The system SHALL provide realized profit queries for four periods: today, current month, previous three months, and a user-specified date range. The system SHALL filter sales by sale date, because realized profit is recognized on the sale date. The system SHALL report the realized profit total, the number of sales included, and the transaction fees and tax deducted, for each period.

#### Scenario: Querying today's realized profit
- **WHEN** two sales were recorded on 2026-03-05 with realized profits of 5000 and -2000, and the user queries today on 2026-03-05
- **THEN** the system reports a realized profit total of 3000 from 2 sales

#### Scenario: Querying the previous three months
- **WHEN** sales exist dated 2026-01-10, 2026-02-15, and 2026-03-05, and the user queries the previous three months on 2026-03-10
- **THEN** the system includes all three sales in the result

#### Scenario: Querying a custom range
- **WHEN** the user queries the range 2026-02-01 to 2026-02-28
- **THEN** the system includes the sale dated 2026-02-15 and excludes the sales dated 2026-01-10 and 2026-03-05

#### Scenario: Period with no sales
- **WHEN** the user queries a period that contains no sales
- **THEN** the system reports a realized profit total of 0 and 0 sales

### Requirement: Realized profit by symbol and by sale
The system SHALL allow the user to view the realized profit result grouped by stock symbol as well as as a single list of individual sales. Each sale entry SHALL display the sale date, symbol, sale quantity, sale price, the lot or lots it was allocated to, and the resulting realized profit.

#### Scenario: Grouping by symbol
- **WHEN** the user selects symbol 2330 for a realized profit query covering 2026-03-01 to 2026-03-31 and two sales of 2330 occurred in that range
- **THEN** the system reports one group for 2330 whose total equals the sum of those two sales' realized profits, and excludes any other symbol's sales

### Requirement: Fee and tax handling on sales
The system SHALL record, for every sale, the commission and the Taiwan stock transaction tax at 0.3 percent of the sale value, and SHALL deduct both from the realized profit. The system SHALL read the commission rate from the settings store and SHALL apply the rate in effect when the sale was recorded. The system SHALL discard the fractional dollar of every fee and tax it records, because brokerages charge whole dollars. The system SHALL also record the 0.4 percent securities transaction tax as a reference figure for the sale, without deducting it from realized profit, because Taiwan assesses that tax at annual settlement rather than per trade.

#### Scenario: Sale fees and taxes
- **WHEN** the user records a sale of 1000 shares at 130 with a commission rate of 0.1425 percent
- **THEN** the system records commission of 185, transaction tax of 390, a reference securities transaction tax figure of 520, and deducts commission and transaction tax from realized profit

##### Example: the fractional dollar is discarded
| Quantity | Price per share | Commission before truncation | Commission recorded | Transaction tax recorded |
| --- | --- | --- | --- | --- |
| 1000 | 130 | 185.25 | 185 | 390 |
| 50 | 1300 | 92.625 | 92 | 195 |

#### Scenario: Commission rate change does not alter past sales
- **WHEN** a sale was recorded with a commission rate of 0.1425 percent and the user later changes the rate to 0.15 percent
- **THEN** the system continues to report the past sale using the rate recorded on that sale
