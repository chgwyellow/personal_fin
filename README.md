# FinTrack

[English](README.md) · [繁體中文](README.zh-TW.md)

[![Version](https://img.shields.io/github/v/tag/chgwyellow/personal_fin?label=version)](https://github.com/chgwyellow/personal_fin/tags)
[![Downloads](https://img.shields.io/github/downloads/chgwyellow/personal_fin/total?label=downloads)](https://github.com/chgwyellow/personal_fin/releases)
[![macOS](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](https://github.com/chgwyellow/personal_fin/releases)
[![Swift](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-native-orange?logo=swift&logoColor=white)](https://developer.apple.com/xcode/swiftui/)
[![SQLite](https://img.shields.io/badge/SQLite-local-003B57?logo=sqlite&logoColor=white)](https://www.sqlite.org/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

<p align="center">
  <img src="docs/assets/fintrack-hero.png" alt="FinTrack Overview and Portfolio" width="100%">
</p>

<h3 align="center">Your finances. One clear picture.</h3>

<p align="center">
  A private, local-first personal finance app for macOS.<br>
  Track what you own, what you owe, how your investments are performing,
  and how your net worth changes over time.
</p>

## Your financial life, in one place

FinTrack brings the different parts of your personal finances together so you
can understand your overall financial position without handing your financial
information to an online account or subscription service.

Manage cash, assets, liabilities, investments, dividends, recurring
investments, and foreign-currency balances while keeping your financial
database on your own Mac.

Market prices and exchange rates are fetched when needed to calculate current
values. Your manually entered information, transactions, balances, and
snapshots remain stored locally.

## What you can do with FinTrack

### See your complete financial picture

Track assets, liabilities, investments, and net worth together instead of
maintaining separate lists or spreadsheets. Create snapshots to see how your
net worth changes over time.

### Understand your investments

Track Taiwan and U.S. stocks and ETFs in their original currencies. View
portfolio value, allocation, capital gains, and daily profit and loss while
keeping your actual purchase information locally.

FinTrack is designed for portfolio tracking and personal financial analysis,
not active trading.

### Keep recurring investments organized

Create recurring investment plans and enter the purchases you actually make.
FinTrack keeps the investment plan separate from completed purchases so your
portfolio reflects your actual holdings.

### Track dividends and income

Manage dividends and income-statement items alongside the rest of your
financial information.

### Manage foreign currencies

Track foreign-currency balances, exchange rates, and transactions alongside
your other assets.

### Build a history of your net worth

Create manual or scheduled net worth snapshots and view your history across
selectable time ranges. Snapshots help you understand how your overall
financial position changes instead of looking only at today's numbers.

## Private by design

FinTrack does not require an account or sign-in. It does not operate a backend
server for storing user data. Your financial database is stored locally on
your Mac using SQLite and is never uploaded to FinTrack.

External public data sources are contacted only when information such as market
prices or exchange rates is needed.

> **Your financial information stays on your Mac.**

## What FinTrack is — and what it isn't

FinTrack is a **personal finance tracking and analysis tool**. It is designed
to help answer questions such as:

- What do I own?
- What do I owe?
- What is my current net worth?
- How is my investment portfolio performing?
- How is my money allocated?
- How has my financial position changed over time?

FinTrack is not a brokerage or trading terminal. It does not place stock
orders, connect to brokerage accounts, automatically import brokerage
transactions, move money, or execute recurring investments automatically.

Completed investment transactions and recurring purchases must be entered
manually.

## Core features

- **Financial Overview** — Track assets, liabilities, investments, and net worth
  in one place
- **Net Worth History** — Create manual and scheduled snapshots and view
  historical changes
- **Portfolio Tracking** — Track Taiwan and U.S. stocks and ETFs in their
  original currencies
- **Portfolio Analytics** — View portfolio value, allocation, capital gains,
  and daily profit and loss
- **Recurring Investments** — Manage recurring investment plans and completed
  purchases
- **Dividends & Income** — Manage dividends and income-statement items
- **Foreign Currency** — Track foreign-currency balances, exchange rates, and
  transactions
- **Local Storage** — Store financial information locally using SQLite

## Download the test release

### Download step by step

1. Open [GitHub Releases](https://github.com/chgwyellow/personal_fin/releases).
2. Open the newest release, such as `v0.1.2`.
3. Scroll to **Assets** and expand it if necessary.
4. Download **`FinTrack-0.1.2.zip`**.
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
the app does not remove this database.

Before testing a new release, back up the database:

```bash
cp "$HOME/Library/Application Support/FinTrack/personal_finance.db" \
   "$HOME/Library/Application Support/FinTrack/personal_finance.backup.db"
```

## Getting started

1. Add your assets and liabilities from **Overview**.
2. Add stocks or ETFs from **Portfolio** and manage their actual purchases.
3. Use **Recurring Investment** to manage recurring investment plans.
4. Add foreign-currency balances and transactions from **Foreign Currency**.
5. Create a snapshot from **Overview** to start tracking your net worth history.
6. Open **Help** inside FinTrack for page-specific guidance.

Market prices and exchange rates are refreshed when relevant pages are opened.
Scheduled snapshots run while the Mac is available to run the app.

## Known limitations

- macOS only; the current release artifact supports Apple Silicon only
- The test release has no Apple Developer ID signature, notarization, or
  automatic updater
- Market-data availability depends on external public APIs and supported
  symbols

## Report a problem

If you find a bug or something that is unclear, please [open a GitHub
Issue](https://github.com/chgwyellow/personal_fin/issues/new).

When possible, include:

- The FinTrack version and macOS version
- The page or feature where the problem occurred
- Steps to reproduce the problem
- The expected result and what actually happened
- A screenshot or screen recording, if it helps explain the problem
