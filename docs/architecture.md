# FinTrack Architecture

## Overview

FinTrack is a native macOS application. The production app is implemented in
Swift and SwiftUI, with SQLite used for local persistence. It does not require
Python, a separate server, an account, or a sign-in service.

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

## Python code

The Python modules in `src/` and tests in `tests/` were created during the early
prototype and domain-model development of FinTrack. They helped explore the
data model, calculations, and expected behavior, but they are not part of the
production macOS application.

The Python code uses a separate development database:

```text
data/personal_finance.db
```

The Python environment is therefore optional and is not packaged with the macOS
application. Running the released App does not import, execute, or depend on
any Python module.

## Why the production app uses Swift

Swift keeps the distributed app self-contained and native to macOS. Users do
not need to install Python or manage a Python runtime, and the same application
bundle can be distributed as a standalone App, ZIP, DMG, or Homebrew Cask.

The current Swift implementation is the source of truth for production
behavior. Python code should not be treated as a second runtime or as a live
backend.

## Future cleanup

The Python prototype may be retained temporarily for historical context and
reference. If it is no longer useful, it can later be archived or removed from
the main branch without affecting the macOS application. Git history will still
preserve the earlier implementation.
