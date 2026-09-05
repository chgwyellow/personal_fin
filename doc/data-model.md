# Personal Finance — Initial Data Model

## 1. Design principles

NTD is the project's internal label for the New Taiwan dollar. External
providers may require the standard code `TWD`; provider adapters must map
between that code and `NTD` in both directions.

- SQLite is the local source of truth.
- All monetary records retain their original currency.
- Balance-sheet values are converted to NTD for reporting.
- Portfolio prices, costs, market values, and performance are calculated in
  the security's original currency.
- Holdings are investments and therefore a type of asset.
- Confirmed recurring-investment executions are persisted so changes can be
  reviewed and rolled back.
- Calculated values should not be stored unless they represent a historical
  snapshot or a cached external value.

## 2. Entity relationship overview

```text
assets ───────────────┐
  │                   │
  └── holdings ───────┼── recurring_investments
          │           │          │
          │           │          └── recurring_investment_executions
          │           │
          ├── dividends
          └── market_prices

liabilities
exchange_rates
snapshots
```

## 3. Tables

### 3.1 `assets`

Stores all assets, including cash, investments, and other assets.

| Column | Type | Required | Description |
| --- | --- | ---: | --- |
| `id` | INTEGER | Yes | Primary key |
| `name` | TEXT | Yes | User-facing name |
| `asset_group` | TEXT | Yes | `liquid_asset`, `liquid_investment`, or `other_asset` |
| `category` | TEXT | Yes | Examples: bank account, U.S. ETF, pension fund |
| `currency` | TEXT | Yes | Project currency label such as `NTD` or `USD` |
| `value` | NUMERIC | Yes | Current value in original currency |
| `notes` | TEXT | No | User notes |
| `is_active` | INTEGER | Yes | Boolean, default `1` |
| `created_at` | TEXT | Yes | Taiwan time |
| `updated_at` | TEXT | Yes | Taiwan time |

The application provides default categories and allows custom categories.

### 3.2 `holdings`

Stores investment-specific information for an asset. One asset may have one
holding record when the asset represents a stock or ETF.

| Column | Type | Required | Description |
| --- | --- | ---: | --- |
| `id` | INTEGER | Yes | Primary key |
| `asset_id` | INTEGER | Yes | Foreign key to `assets` |
| `symbol` | TEXT | Yes | Yahoo Finance symbol |
| `security_name` | TEXT | Yes | Display name |
| `market` | TEXT | Yes | `TW` or `US` initially |
| `currency` | TEXT | Yes | Security's original currency |
| `shares` | NUMERIC | Yes | Current quantity |
| `total_cost` | NUMERIC | Yes | Total cost in original currency |
| `dividend_total` | NUMERIC | Yes | Manually entered dividends in original currency, default `0` |
| `created_at` | TEXT | Yes | Taiwan time |
| `updated_at` | TEXT | Yes | Taiwan time |

`average_cost` is calculated and should not be the source of truth:

```text
average_cost = total_cost / shares
```

The current market price and market value come from `market_prices` and are
not stored as permanent holding values.

### 3.3 `recurring_investments`

Stores recurring investment plans.

| Column | Type | Required | Description |
| --- | --- | ---: | --- |
| `id` | INTEGER | Yes | Primary key |
| `holding_id` | INTEGER | Yes | Foreign key to `holdings` |
| `planned_amount` | NUMERIC | Yes | Planned amount in original currency |
| `currency` | TEXT | Yes | Plan currency |
| `frequency` | TEXT | Yes | For example monthly |
| `execution_day` | INTEGER | Yes | Planned day of month |
| `start_date` | TEXT | Yes | Date in Taiwan time |
| `end_date` | TEXT | No | Optional end date |
| `is_active` | INTEGER | Yes | Boolean, default `1` |
| `notes` | TEXT | No | User notes |

### 3.4 `recurring_investment_executions`

Stores each confirmed simulated execution. This is the rollback and audit
basis; it must not be discarded after updating a holding.

| Column | Type | Required | Description |
| --- | --- | ---: | --- |
| `id` | INTEGER | Yes | Primary key |
| `recurring_investment_id` | INTEGER | No | Related plan; nullable for manual execution |
| `holding_id` | INTEGER | Yes | Foreign key to `holdings` |
| `execution_date` | TEXT | Yes | Date/time in Taiwan time |
| `invested_amount` | NUMERIC | Yes | Total cost in original currency |
| `currency` | TEXT | Yes | Original currency |
| `shares_purchased` | NUMERIC | Yes | Shares or units purchased |
| `purchase_price` | NUMERIC | Yes | Price per share or unit |
| `status` | TEXT | Yes | `confirmed`, `reversed`, or `cancelled` |
| `created_at` | TEXT | Yes | Taiwan time |
| `notes` | TEXT | No | User notes |

When confirmed, the execution updates `holdings.shares` and
`holdings.total_cost`. Reversal should create a compensating change and keep
the original record for history.

### 3.5 `dividends`

Stores manually entered dividends.

| Column | Type | Required | Description |
| --- | --- | ---: | --- |
| `id` | INTEGER | Yes | Primary key |
| `holding_id` | INTEGER | Yes | Foreign key to `holdings` |
| `received_date` | TEXT | Yes | Date in Taiwan time |
| `amount` | NUMERIC | Yes | Dividend in original currency |
| `currency` | TEXT | Yes | Original currency |
| `notes` | TEXT | No | User notes |

`holdings.dividend_total` may be a cached total; the dividend records remain
the source of truth.

### 3.6 `liabilities`

| Column | Type | Required | Description |
| --- | --- | ---: | --- |
| `id` | INTEGER | Yes | Primary key |
| `name` | TEXT | Yes | User-facing name |
| `liability_group` | TEXT | Yes | `short_term` or `long_term` |
| `category` | TEXT | Yes | User-defined or default category |
| `currency` | TEXT | Yes | Original currency |
| `balance` | NUMERIC | Yes | Current balance in original currency |
| `interest_rate` | NUMERIC | No | Annual rate |
| `due_date` | TEXT | No | Date in Taiwan time |
| `notes` | TEXT | No | User notes |
| `created_at` | TEXT | Yes | Taiwan time |
| `updated_at` | TEXT | Yes | Taiwan time |

### 3.7 `market_prices`

Stores the last successful price received from a provider.

| Column | Type | Required | Description |
| --- | --- | ---: | --- |
| `id` | INTEGER | Yes | Primary key |
| `symbol` | TEXT | Yes | Provider symbol |
| `market` | TEXT | Yes | Market identifier |
| `price` | NUMERIC | Yes | Price in original currency |
| `currency` | TEXT | Yes | Price currency |
| `observed_at` | TEXT | Yes | Provider observation time |
| `retrieved_at` | TEXT | Yes | Local retrieval time in Taiwan time |
| `source` | TEXT | Yes | For example `yahoo_finance` |

Failed updates must not overwrite the last successful record. Multiple price
records may be retained for historical use, with the newest successful record
used for current valuation.

### 3.8 `exchange_rates`

| Column | Type | Required | Description |
| --- | --- | ---: | --- |
| `id` | INTEGER | Yes | Primary key |
| `base_currency` | TEXT | Yes | For example `USD` |
| `quote_currency` | TEXT | Yes | For example `NTD` |
| `rate` | NUMERIC | Yes | Quote currency per base currency |
| `observed_at` | TEXT | Yes | Provider observation time |
| `retrieved_at` | TEXT | Yes | Local retrieval time in Taiwan time |
| `source` | TEXT | Yes | For example `yahoo_finance` |

Taiwan securities do not require FX conversion. U.S. securities are converted
from USD to NTD for balance-sheet reporting.

### 3.9 `snapshots`

Stores historical balance-sheet values and selected portfolio totals.

| Column | Type | Required | Description |
| --- | --- | ---: | --- |
| `id` | INTEGER | Yes | Primary key |
| `snapshot_date` | TEXT | Yes | Date in Taiwan time |
| `total_assets_ntd` | NUMERIC | Yes | Total assets in NTD |
| `total_liabilities_ntd` | NUMERIC | Yes | Total liabilities in NTD |
| `net_worth_ntd` | NUMERIC | Yes | Net worth in NTD |
| `portfolio_value_ntd` | NUMERIC | Yes | Portfolio value in NTD |
| `asset_allocation_json` | TEXT | No | Allocation at snapshot time |
| `created_at` | TEXT | Yes | Taiwan time |

## 4. Reporting calculations

Portfolio calculations use original currency:

```text
capital_gain_loss = market_value - total_cost
total_gain_loss = capital_gain_loss + dividend_total
capital_return_rate = capital_gain_loss / total_cost
total_return_rate = total_gain_loss / total_cost
```

Balance-sheet calculations use NTD-converted values:

```text
total_assets = liquid_assets + liquid_investments + other_assets
net_worth = total_assets - total_liabilities
free_cash_flow = net_worth - fixed_assets
cash_ratio = liquid_assets - total_liabilities
equity_multiplier = total_assets / net_worth
net_worth_growth_rate = (current_net_worth - previous_net_worth) / previous_net_worth
```

Division-by-zero results should be represented as unavailable, not zero.

## 5. Open implementation decisions

- Whether `dividend_total` should be cached on `holdings` or calculated every time
- Whether a reversed execution stores a compensating execution row or a reversal reference
- Exact SQLite constraints and indexes
- Exact Yahoo Finance symbol format for Taiwan securities
