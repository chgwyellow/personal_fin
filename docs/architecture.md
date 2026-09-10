# FinTrack Architecture

## Overview

FinTrack is a native macOS application implemented in Swift and SwiftUI, with
SQLite used for local persistence. It does not require a separate server, an
account, or a sign-in service.

## Production application

The macOS app is built from `Sources/PersonalFinanceApp/`:

- `PersonalFinanceApp.swift` contains the SwiftUI views, app state, calculations,
  scheduling, and user interactions.
- `DatabaseManager.swift` provides the SQLite schema, migrations, queries, and
  writes used by the app.
- `MarketDataClient.swift` and `YahooMarketStream.swift` handle market data and
  price updates.
- `Sources/CSQLite/` exposes the system SQLite library to Swift.

The app stores user data at:

```text
~/Library/Application Support/FinTrack/personal_finance.db
```

The database directory, database file, and tables are created automatically on
the first launch. Each macOS user account has its own database.

## Why the app uses Swift

Swift keeps the distributed app self-contained and native to macOS. Users do
not need to install or manage a separate runtime, and the same application
bundle can be distributed as a standalone App, ZIP, DMG, or Homebrew Cask.

The current Swift implementation is the source of truth for production
behavior.
