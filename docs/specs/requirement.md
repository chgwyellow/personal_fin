# Personal Finance — MVP Requirements

## 1. Document purpose

This document defines the functional requirements for the first usable version of Personal Finance: a local-first personal net-worth tracker that can replace the current Google Sheets workflow. It is not accounting or tax software.

## 2. Terminology

- **Asset**: something owned by the user.
- **Liability**: something owed by the user.
- **Holding**: an investment position in a security.
- **Portfolio**: the collection of investment holdings and their valuation.
- **Reporting currency**: the currency used for summaries; NTD is the MVP default.
- **Snapshot**: a point-in-time record of assets, liabilities, and net worth.

## 3. Assets

The user must be able to create, view, edit, and delete assets.

Each asset includes:

- Name
- Category
- Currency
- Current value or balance
- Optional notes
- Created and updated timestamps

Initial categories:

- Liquid assets: bank accounts, cash, and foreign currency
- Investments: stocks, ETFs, bonds, and crypto assets
- Other assets: deposits, pension-related assets, property, vehicles, and precious metals

The application should provide these categories by default and allow the user
to add custom categories.

The system must show total assets in the reporting currency.

For balance-sheet reporting, assets are grouped into:

- **Liquid assets**: bank accounts, cash, foreign currency, brokerage cash, and similar immediately available funds
- **Liquid investments**: stocks and ETFs that can be sold relatively easily
- **Other assets**: pension funds, deposits, property, vehicles, precious metals, and other manually valued assets

Each group must show its line items, group total, and percentage of total
assets. Balance-sheet amounts are converted to NTD; this does not change the
original-currency values used by portfolio reporting.

## 4. Liabilities

The user must be able to create, view, edit, and delete liabilities.

Each liability includes name, category, currency, current balance, and optional interest rate, due date, term, and notes.

Initial categories are short-term liabilities (term shorter than five years) and long-term liabilities (term of five years or longer). The system must show total liabilities in the reporting currency.

For balance-sheet reporting, liabilities are grouped into short-term and
long-term liabilities. Each group must show its line items, group total, and
percentage of total liabilities.

## 5. Net worth and indicators

```text
Total assets = sum of all asset values
Total liabilities = sum of all liability balances
Net worth = total assets - total liabilities
Liability ratio = total liabilities / total assets
Free cash flow = net worth - fixed assets
Cash ratio = liquid assets - total liabilities
Equity multiplier = total assets / net worth
Net-worth growth rate = (current net worth - previous net worth) / abs(previous net worth)
```

The dashboard should also show asset allocation by category and the value of
other assets. For this project, fixed assets are the non-liquid assets recorded
under the “other assets” category.

The balance sheet shows total assets, total liabilities, net worth, and the
four indicators above in NTD where the result is monetary. Net-worth growth
requires a previous snapshot; if no previous snapshot exists, the result must
be shown as unavailable rather than zero.

## 6. Investment portfolio

Yes, portfolio requirements should be included. Portfolio tracking is a core MVP capability, but it is separated here because holdings have different data and calculation rules from ordinary assets.

### 6.1 Holdings

The user must be able to record and edit holdings with:

- Symbol
- Security name
- Market
- Currency
- Number of shares or units
- Average cost per share or unit

The MVP supports Taiwan and U.S. stocks and ETFs. Bonds and crypto may initially be recorded as manually valued assets unless separate valuation rules are needed.

### 6.2 Portfolio calculations

```text
Cost basis = quantity × average cost
Market value = quantity × current market price
Capital gain/loss = market value - cost basis
Return rate = unrealized gain/loss / cost basis
Portfolio weight = market value / total portfolio market value
Total gain/loss = capital gain/loss + dividends
```

The system must show portfolio totals in the reporting currency. Investment amounts normally include transaction fees, so the MVP treats the user-entered amount as total cost and does not calculate fees separately.

The average cost is calculated as:

```text
Average cost = total cost / total shares
```

Dividends are entered manually in the security's original currency and added
directly to total gain/loss. They do not change the holding's cost basis. Stock
splits may be represented by adjusting the share quantity while keeping total
cost unchanged; the average cost is then recalculated. Transaction fees are
normally included in the invested amount; if unavailable, they may be ignored.

### 6.3 Recurring investments

The user may define a recurring investment plan for a stock or ETF. A plan should include:

- Security
- Planned investment amount
- Currency
- Frequency
- Planned execution day
- Start date
- Optional end date
- Active/inactive status
- Optional notes

When a plan is due, the application should provide a pop-up simulated execution record. The user can enter or confirm:

- Actual invested amount, including fees
- Shares or units purchased
- Purchase price, if needed for verification
- Execution date

The user must explicitly confirm the simulated execution before it changes the holding's quantity, total cost, and average cost. Confirmed records must be retained as the basis for review and rollback. Automatic brokerage execution and automatic transaction importing are out of scope.

Whether confirmed simulated execution records require their own persistent table remains an open data-model decision.

### 6.4 Market data

The system should update latest security prices and required exchange rates. It must retain the last successful value, timestamp, and source. A failed update must not erase the previous value. The provider should be replaceable and isolated from portfolio calculations.

For the MVP, follow the StockDock approach and use Yahoo Finance as the market
data source for Taiwan securities, U.S. securities, and currency pairs such as
USD/NTD. Use Yahoo Finance's WebSocket endpoint for live price updates where
available, and its REST endpoints for exchange rates and fallback refreshes.
The provider must remain behind a replaceable interface. If the application is
later distributed commercially, the current Yahoo Finance terms and any
required market-data licensing must be reviewed before release.

## 7. Currency

- NTD is the default reporting currency.
- Each asset, liability, and holding retains its original currency.
- Taiwan securities are valued in NTD and do not require currency conversion.
- U.S. securities are valued in USD and converted to NTD for portfolio
  summaries.
- Converted values must identify the exchange-rate timestamp or date and source.
- Missing exchange rates must show a warning, never a silent or zero-valued conversion.
- Dates and timestamps are interpreted and displayed using Taiwan time
  (`Asia/Taipei`).

## 8. Historical snapshots

The user must be able to create a snapshot manually containing snapshot date, total assets, total liabilities, net worth, portfolio value, and optionally asset allocation. The system should display net-worth history. Automatic periodic snapshots are optional for the MVP.

## 9. Data ownership and portability

Financial data stays local by default; no account or cloud database is required. The user must be able to back up and restore the local database and export data to at least CSV or JSON. Public market-data requests may access the internet, but personal balances, holdings, and history must not be transmitted.

## 10. Validation and error handling

- Reject negative quantities where they are not meaningful.
- Require a currency for monetary values.
- Require symbol, market, quantity, and average cost for a holding.
- Prevent division-by-zero errors in ratios and return rates.
- Clearly identify stale or unavailable market data.
- Preserve user-entered data when an external update fails.

## 11. MVP exclusions

- Bank or brokerage API integration
- Automatic transaction importing
- Full transaction-level portfolio accounting
- Cloud synchronization and user accounts
- Budgeting and expense categorization
- Tax reporting or financial advice
- Real-time trading or order execution
- Mobile application

## 12. Acceptance criteria

The MVP is usable when the user can:

1. Record assets and liabilities in multiple currencies.
2. View total assets, total liabilities, and net worth in NTD.
3. Record Taiwan and U.S. stock or ETF holdings.
4. View cost basis, market value, gain/loss, and portfolio weight.
5. Update prices and exchange rates without losing prior data.
6. Create and review historical net-worth snapshots.
7. Back up and export local data.

## 13. Open decisions

- Exact categories used in the current spreadsheet
- How dividend entries are edited or deleted after being recorded
- Whether the recurring-investment pop-up should support editing a previously confirmed execution
