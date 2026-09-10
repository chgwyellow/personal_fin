# Personal Finance --- Project Plan

> **Working title:** Personal Finance\
> **Project type:** Local-first personal net worth & investment
> portfolio tracker\
> **Initial platform:** Desktop\
> **Project status:** Idea / Planning\
> **Infrastructure cost target:** \$0/month during early development

------------------------------------------------------------------------

## 1. Project Vision

**Personal Finance** is a lightweight personal finance application
designed to replace spreadsheet-based asset tracking with a cleaner,
more convenient user interface.

The project is **not intended to be professional accounting software**.
Its primary purpose is to help an individual answer a few simple
questions:

- How much do I own?
- How much do I owe?
- What is my current net worth?
- How are my assets allocated?
- How are my investments performing?
- How has my financial position changed over time?

The core equation is intentionally simple:

\[ `\text{Net Worth}`{=tex} = `\text{Total Assets}`{=tex} -
`\text{Total Liabilities}`{=tex} \]

The initial product philosophy is:

> **Simple enough for personal use, powerful enough to replace a
> spreadsheet.**

------------------------------------------------------------------------

## 2. Problem Statement

The current workflow uses Google Sheets to maintain:

- Assets
- Liabilities
- Net worth
- Investment positions
- Portfolio allocation
- Investment returns
- Historical quarterly snapshots
- Personal financial health indicators

Google Finance can provide some market prices, but the spreadsheet
workflow has several limitations:

1. The interface is designed for spreadsheets rather than personal
    finance.
2. Data entry and presentation are mixed together.
3. Portfolio and net-worth information require manually maintained
    formulas and charts.
4. Multi-currency portfolios, especially NTD-based portfolios
    containing both Taiwan and U.S. securities, are not handled
    elegantly by many existing portfolio applications.
5. Existing desktop tools may support securities but not NTD as the
    user's base/reporting currency.
6. The user should retain ownership of sensitive personal financial
    data rather than being required to upload it to a third-party cloud
    service.

Personal Finance aims to solve these problems while keeping the scope
intentionally small.

------------------------------------------------------------------------

## 3. Target User

### Primary user

The initial user is the developer.

This is intentional: the project should solve a real, recurring personal
problem before attempting to serve a broader audience.

### Potential future users

If the project proves useful, it may eventually serve:

- Taiwan-based investors
- Investors holding both Taiwan and U.S. securities
- Multi-currency investors
- People currently tracking net worth with Excel or Google Sheets
- Users who prefer local-first financial software
- Users who want a simple alternative to complex accounting
    applications

------------------------------------------------------------------------

## 4. Product Principles

### 4.1 Local-first

Personal financial data should remain on the user's device by default.

Early versions should not require:

- Cloud accounts
- User registration
- Hosted databases
- Monthly infrastructure costs

### 4.2 NTD-first, multi-currency capable

The application should support **NTD as a first-class base currency**.

Assets may be denominated in currencies such as:

- NTD
- USD
- JPY
- EUR

All assets should be convertible into the user's selected reporting
currency.

### 4.3 Taiwan + international investments

The portfolio model should be capable of representing:

- Taiwan stocks
- Taiwan ETFs
- U.S. stocks
- U.S. ETFs

Additional markets may be considered later.

### 4.4 Simple financial model

The application is a **personal net-worth tracker**, not a general
ledger or professional accounting system.

Avoid unnecessary complexity such as:

- Double-entry accounting
- IFRS/GAAP reporting
- Enterprise accounting workflows
- Tax accounting engines

unless future product requirements genuinely justify them.

### 4.5 User owns the data

Users should be able to:

- Back up their database
- Restore a backup
- Export their data
- Continue accessing their data even if the project is discontinued

### 4.6 Build before scaling

Do not design infrastructure for hypothetical large-scale usage.

Early development target:

**Infrastructure cost = \$0/month**

------------------------------------------------------------------------

## 5. MVP Scope

The first meaningful milestone is:

> **Personal Finance can replace the existing Google Sheets workflow for
> day-to-day asset tracking.**

### 5.1 Assets

Users can create, edit, and delete assets.

Example categories:

- Liquid assets
  - Bank deposits
  - Brokerage cash
  - Foreign currency
- Investments
  - Taiwan stocks
  - Taiwan ETFs
  - U.S. stocks
  - U.S. ETFs
- Other assets
  - Deposits
  - Pension-related assets
  - Other manually valued assets

### 5.2 Liabilities

Users can record liabilities including:

- Name
- Current balance
- Type
- Interest rate
- Currency

Possible categories:

- Short-term liabilities
- Long-term liabilities

### 5.3 Net Worth

Automatically calculate:

- Total assets
- Total liabilities
- Net worth
- Liability ratio
- Asset allocation

The balance sheet should present all monetary values in NTD. Assets should be
split into liquid assets, liquid investments, and other assets, with line items
and section totals. Liabilities should be split into short-term and long-term
liabilities, also with line items and group totals. This is separate from the
portfolio view, where prices, costs, market values, and performance remain in
the security's original currency.

The balance-sheet indicators are defined as follows:

- Free cash flow = net worth - fixed assets
- Cash ratio = liquid assets - total liabilities
- Equity multiplier = total assets / net worth
- Net-worth growth rate = (current net worth - previous net worth) / abs(previous net worth)

Fixed assets are represented by non-liquid assets in the “other assets” group.

### 5.4 Investment Portfolio

Each holding should support at least:

- Symbol
- Market
- Currency
- Number of shares
- Average cost
- Current market price
- Cost basis
- Market value
- Capital gain/loss
- Return rate
- Portfolio weight

The MVP should also support recurring investment plans for stocks and ETFs.
When a plan is due, the user should be able to open a pop-up simulated
execution record and enter the actual invested amount, shares purchased,
purchase price, and execution date. The user must confirm the record before it
updates the holding. Confirmed records must be retained for review and rollback.

Investment amounts normally include transaction fees; if fee data is
unavailable, fees may be ignored. Dividends are entered manually in the
security's original currency and added to total gain/loss, while capital
gain/loss remains market value minus cost basis. Stock splits may be represented
by adjusting shares while keeping total cost unchanged, then recalculating
average cost. Full transaction-level portfolio accounting is not required for
the MVP.

### 5.5 Market Data

Where technically and legally practical, automatically retrieve:

- Current/latest security prices
- NTD/USD exchange rate
- Other required FX rates

Market-data providers should remain replaceable rather than tightly
coupled to the portfolio model.

For the MVP, follow the StockDock approach and use Yahoo Finance for Taiwan
securities, U.S. securities, and FX. Use Yahoo Finance WebSocket for live price
updates where available, and REST endpoints for exchange rates and fallback
refreshes. Keep this behind a replaceable provider interface. If the project
later becomes a commercial product, review Yahoo's current terms and market-data
licensing before release.

### 5.6 Historical Snapshots

Periodically record financial snapshots containing values such as:

- Total assets
- Total liabilities
- Net worth
- Asset allocation
- Portfolio value

Initial snapshots may be manually triggered or generated periodically.

### 5.7 Dashboard

The UI should eventually present:

- Net worth
- Assets
- Liabilities
- Asset allocation
- Portfolio allocation
- Investment performance
- Net-worth history
- Selected personal finance indicators

------------------------------------------------------------------------

## 6. Explicitly Out of Scope for MVP

To prevent scope creep, the following are **not required** for the first
version:

- Bank API integration
- Brokerage account integration
- Automatic transaction importing
- Cloud synchronization
- User accounts
- Multi-user support
- Mobile application
- Professional accounting
- Tax reporting
- Budgeting system
- Credit-card transaction categorization
- AI financial advice
- Real-time trading
- Brokerage order execution
- Subscription system
- App Store payment integration

These may be reconsidered only after the core application is genuinely
useful.

------------------------------------------------------------------------

## 7. Initial Data Model

The exact schema should evolve during implementation. Conceptually, holdings
are a type of asset rather than a completely separate financial domain. The
implementation may use one shared asset record with investment-specific
details, provided portfolio calculations remain clear.

### Accounts / Assets

Potential fields:

- `id`
- `name`
- `category`
- `currency`
- `balance`
- `notes`
- `created_at`
- `updated_at`

### Liabilities

Potential fields:

- `id`
- `name`
- `category`
- `currency`
- `balance`
- `interest_rate`
- `notes`

### Holdings

Potential fields:

- `id`
- `symbol`
- `name`
- `market`
- `currency`
- `shares`
- `average_cost`

### Recurring Investment Plans

Potential fields:

- `id`
- `holding_id` or security reference
- `amount`
- `currency`
- `frequency`
- `execution_day`
- `start_date`
- `end_date`
- `is_active`
- `notes`

Whether confirmed simulated execution records require a separate table is
still an implementation detail; the records must nevertheless be persisted.

### Recurring Investment Executions

Potential fields:

- `id`
- `recurring_investment_id`
- `execution_date`
- `invested_amount`
- `currency`
- `shares_purchased`
- `purchase_price`
- `status`

### Market Prices

Potential fields:

- `symbol`
- `price`
- `currency`
- `timestamp`
- `source`

### Exchange Rates

Potential fields:

- `base_currency`
- `quote_currency`
- `rate`
- `timestamp`
- `source`

### Snapshots

Potential fields:

- `snapshot_date`
- `total_assets`
- `total_liabilities`
- `net_worth`
- `portfolio_value`

The schema should be normalized only where doing so improves correctness
and maintainability. Premature complexity should be avoided.

Taiwan securities are valued in NTD without FX conversion. U.S. securities are
valued in USD and converted to NTD for summaries. Dates and timestamps use
Taiwan time (`Asia/Taipei`).

------------------------------------------------------------------------

## 8. Proposed Technical Direction

This section records the current direction rather than a permanent
decision.

### Phase 1 --- Core Prototype

Possible stack:

- SQLite
- Lightweight prototype UI
- External market/FX data source

Goals:

- Validate calculations
- Validate data model
- Reproduce the existing spreadsheet workflow
- Determine whether the application is genuinely more convenient than
    Google Sheets

### Why SQLite?

SQLite is suitable because:

- It runs locally.
- It does not require a database server.
- It has no hosting cost.
- A personal finance application has relatively small data volume.
- Each user can own an independent database.
- Backup/export can be straightforward.
- It supports a local-first architecture.

### Phase 2 --- Desktop Product

Potential direction:

- Tauri
- TypeScript
- React or another suitable frontend framework
- SQLite

This is **not yet a final architecture decision**.

Alternative:

- Swift + SwiftUI for a macOS-native application

The desktop framework should be selected only when the core product
requirements are stable.

### Phase 3 --- Distribution

Potential distribution channels:

- GitHub Releases
- macOS `.dmg`
- Windows installer
- Linux package

Potential future channel:

- Mac App Store

Commercialization is optional and should not influence early
architecture more than necessary.

------------------------------------------------------------------------

## 9. Privacy and Security Direction

Because the application handles sensitive personal financial
information, privacy should be a core product principle.

Initial policy:

> **Financial data stays on the user's device.**

The application should avoid transmitting:

- Asset balances
- Liability balances
- Holdings
- Net worth
- Personal financial history

unless a future feature explicitly requires it and the user knowingly
enables that feature.

Internet access should initially be limited primarily to retrieving
public market and FX data.

Future considerations:

- Local database encryption
- Secure credential storage
- Application sandboxing
- Data export protection
- Backup security

------------------------------------------------------------------------

## 10. Backup and Portability

A local-first application needs a reliable data ownership strategy.

Potential features:

### Backup

- Manual database backup
- Automatic local backups
- Configurable backup retention

### Restore

- Restore from previous Personal Finance backup

### Export

Potential formats:

- SQLite
- CSV
- JSON

The objective is to prevent vendor lock-in and ensure users can retain
their financial history independently of the application.

------------------------------------------------------------------------

## 11. Development Responsibilities

The project can support collaboration rather than requiring one
developer to master every discipline.

### Data / Backend / Core

Potential responsibilities:

- Data modeling
- Database design
- Portfolio calculations
- FX conversion
- Market-data ingestion
- Validation
- Testing
- Application architecture

### Frontend Engineer

Potential responsibilities:

- UI implementation
- Component architecture
- Charts
- Desktop frontend
- React/TypeScript integration if selected

### UI/UX Designer

Potential responsibilities:

- User flows
- Wireframes
- Dashboard design
- Design system
- Usability
- Information hierarchy

### Shared responsibilities

- Product requirements
- Architecture decisions
- Git workflow
- Issues
- Pull requests
- Releases
- Documentation

------------------------------------------------------------------------

## 12. Development Roadmap

### Stage 0 --- Planning

- [x] Identify the problem
- [x] Define high-level scope
- [x] Decide on local-first direction
- [x] Identify NTD support as a key requirement
- [x] Create GitHub repository
- [ ] Write initial README
- [x] Add project plan
- [ ] Define MVP issues
- [x] Decide project license

### Stage 1 --- Requirements

- [ ] Document current Google Sheets workflow
- [ ] List all asset categories
- [ ] List all liability categories
- [ ] Document portfolio calculations
- [ ] Define required financial indicators
- [ ] Define base-currency behavior
- [ ] Define snapshot behavior

### Stage 2 --- Core Domain

- [ ] Design initial data model
- [ ] Create SQLite database
- [ ] Implement assets
- [ ] Implement liabilities
- [ ] Implement net-worth calculation
- [ ] Add unit tests

### Stage 3 --- Portfolio

- [ ] Implement holdings
- [ ] Implement cost basis
- [ ] Implement market value
- [ ] Implement gain/loss
- [ ] Implement portfolio allocation
- [ ] Implement NTD reporting
- [ ] Implement FX conversion
- [ ] Define recurring investment plan model
- [ ] Implement simulated recurring-investment execution flow
- [ ] Define manual dividend handling
- [ ] Define stock-split adjustment behavior

### Stage 4 --- Market Data

- [x] Select Yahoo Finance as the MVP provider, following the StockDock approach
- [ ] Define provider interface
- [ ] Add Taiwan security price retrieval
- [ ] Add U.S. security price retrieval
- [ ] Add FX retrieval
- [ ] Add WebSocket price updates where available
- [ ] Add REST fallback refresh
- [ ] Add caching
- [ ] Add error handling and fallback behavior

### Stage 5 --- Prototype UI

- [ ] Dashboard
- [ ] Asset management
- [ ] Liability management
- [ ] Portfolio view
- [ ] Historical snapshots
- [ ] Charts

### Stage 6 --- Desktop Architecture Decision

Evaluate:

- [ ] Tauri
- [ ] SwiftUI
- [ ] Other reasonable alternatives

Decision criteria:

- Cross-platform support
- Development complexity
- UI quality
- Contributor accessibility
- Packaging
- App Store compatibility
- Maintenance cost
- Fit with available collaborators

### Stage 7 --- Desktop Application

- [ ] Implement selected desktop frontend
- [ ] Integrate SQLite
- [ ] Add settings
- [ ] Add backup/restore
- [ ] Add import/export
- [ ] Package macOS application
- [ ] Publish GitHub Release

### Stage 8 --- Open Source / Product Validation

Only after the application is stable:

- [ ] Improve contributor documentation
- [ ] Add screenshots/demo data
- [ ] Create issue templates
- [ ] Collect user feedback
- [ ] Evaluate Windows/Linux builds
- [ ] Evaluate whether continued open-source development makes sense

### Stage 9 --- Optional Commercialization

Only if real demand exists:

- [ ] Evaluate App Store distribution
- [ ] Review market-data licensing
- [ ] Review privacy/security requirements
- [ ] Evaluate paid vs freemium model
- [ ] Evaluate optional sync
- [ ] Evaluate mobile companion app

------------------------------------------------------------------------

## 13. Success Criteria

### MVP Success

The MVP is successful when:

> **The existing Google Sheets asset-management workflow is no longer
> necessary for normal use.**

More specifically:

- Assets can be recorded easily.
- Liabilities can be recorded easily.
- Net worth is calculated correctly.
- Taiwan and U.S. investments can be represented.
- Portfolio value can be reported in NTD.
- Market values can be updated with minimal manual work.
- Historical net worth can be viewed.
- Data remains local.
- Data can be backed up.

### Project Success

The project is successful even if it never becomes commercial software.

Possible successful outcomes include:

1. It becomes the developer's long-term personal finance tool.
2. It becomes a strong Data Engineering / Software Engineering
    portfolio project.
3. Other users find it useful.
4. Contributors join the project.
5. It becomes a sustainable open-source application.
6. It eventually becomes a paid product.

GitHub stars are welcome, but not a project requirement. ⭐

------------------------------------------------------------------------

## 14. Engineering Learning Goals

Personal Finance can serve as a long-term practical project for
learning:

- Git / GitHub
- SQL
- Relational data modeling
- SQLite
- Testing
- API integration
- Data pipelines
- Error handling
- Logging
- Software architecture
- Documentation
- CI/CD
- Desktop application development
- Collaboration through Issues and Pull Requests

Frontend technologies should be learned only to the depth required by
the project unless the developer intentionally chooses to expand into
frontend engineering.

------------------------------------------------------------------------

## 15. Guiding Rule

Whenever a new feature is proposed, ask:

> **Does this help replace the current spreadsheet workflow or
> materially improve personal asset tracking?**

If the answer is no, the feature should probably wait.

The project should grow from real usage rather than hypothetical
requirements.

------------------------------------------------------------------------

## 16. Current Next Steps

1. Document the current Google Sheets workflow and exact formulas.
2. Confirm the default asset and liability categories.
3. Define the first data model, including persisted recurring-investment
   execution records.
4. Create a small set of GitHub Issues for Stage 1 and Stage 2.
5. Build the SQLite core for assets, liabilities, and net-worth calculation.
6. Add tests before implementing the portfolio and Yahoo Finance integration.
7. Implement the Yahoo Finance provider behind the replaceable provider
   interface.

There is no requirement to rush toward a finished application.

**Build it slowly, understand every layer, and let the product evolve
from actual use.**
