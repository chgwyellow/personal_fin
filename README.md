# FinTrack

[English](README.md) · [繁體中文](README.zh-TW.md)

FinTrack is a privacy-first macOS personal finance app that brings your
financial picture into one place. It helps you understand what you own, what
you owe, how your investments are performing, and how your net worth changes
over time.

FinTrack is designed for people who want a clear personal overview without
handing their financial information to an online account or subscription
service. You can manage cash, investments, liabilities, dividends, recurring purchases,
and foreign-currency balances while keeping the underlying data on your own
Mac.

The app is built around a simple workflow: manage your financial details, let
FinTrack calculate totals and investment values, then use snapshots and history
to see how your overall position changes. Market prices and exchange rates are
used where needed, while your manually entered information remains local.

## Features

- Track assets, liabilities, investments, and net worth
- Create manual and scheduled net worth snapshots
- View net worth history with selectable time ranges
- Track Taiwan and U.S. stocks and ETFs in their original currencies
- Track foreign-currency balances, rates, and transactions
- View portfolio value, allocation, capital gains, and daily profit and loss
- Manage recurring investment plans and actual purchases
- Record dividend and income-statement items
- Store all financial data locally in SQLite

## What FinTrack does not do

FinTrack is a personal tracking and analysis tool. It does not place orders,
connect to brokerage accounts, or automatically import transactions. Completed
investment transactions and recurring purchases must be entered manually.

## Why FinTrack

- **A complete financial overview:** See assets, liabilities, investments, and
  net worth together instead of managing separate lists.
- **Investment-aware tracking:** Follow stocks and ETFs, actual purchases,
  dividends, recurring plans, market value, and daily profit and loss.
- **Useful history:** Create snapshots and compare your financial position over
  time, including month-over-month detail changes.
- **Local by design:** No account or sign-in is required, and your financial
  database stays on your Mac.

## Download the test release

### Download step by step

1. Open [GitHub Releases](https://github.com/chgwyellow/personal_fin/releases).
2. Open the newest release, such as `v0.1.1`.
3. Scroll to **Assets** and expand it if necessary.
4. Download **`FinTrack-0.1.1.zip`**.
5. Open the downloaded ZIP from your Downloads folder.
6. Move the extracted `FinTrack.app` to `/Applications`.
7. Right-click the app and select **Open** on its first launch.
8. If macOS still blocks it, open **System Settings → Privacy & Security** and
   select **Open Anyway**.

The current test release supports Apple Silicon Macs only and is not signed or
notarized. The version number in the filename may change for future releases.

## Data storage and backup

On first launch, FinTrack automatically creates its application-support folder,
SQLite database, and database tables. No manual setup is required.

The database is stored at:

```text
~/Library/Application Support/FinTrack/personal_finance.db
```

Each macOS user account has its own database. Installing, moving, or updating
the app does not remove this database. Back up the database before testing a
new release:

```bash
cp "$HOME/Library/Application Support/FinTrack/personal_finance.db" \
   "$HOME/Library/Application Support/FinTrack/personal_finance.backup.db"
```

## How to use FinTrack

1. Add your assets and liabilities from **Overview**.
2. Add stocks or ETFs from **Portfolio** and manage their actual purchases.
3. Use **Recurring Investment** to manage recurring investment plans.
4. Add foreign-currency balances and transactions from **Foreign Currency**.
5. Create a snapshot from **Overview** to track your net worth history.
6. Open **Help** inside the app for page-specific guidance.

Market prices and exchange rates are refreshed when relevant pages are opened.
Scheduled snapshots run while the Mac is available to run the app.

## Privacy and data safety

FinTrack does not require an account or sign-in. Financial data is stored only
on the user's Mac and is not uploaded by FinTrack.

## Known limitations

- macOS only; the current release artifact supports Apple Silicon only
- The test release has no Apple Developer ID signature, notarization, or
  automatic updater
- Market-data availability depends on external public APIs and supported symbols
- Recurring investment rules do not place trades or import brokerage data
  automatically
