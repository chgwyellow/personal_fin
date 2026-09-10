# Personal Finance

[![Version](https://img.shields.io/badge/version-0.1.0-blue.svg)](https://github.com/chgwyellow/personal_fin)
[![Python](https://img.shields.io/badge/Python-3.14+-3776AB.svg?logo=python&logoColor=white)](https://www.python.org/)
[![SQLite](https://img.shields.io/badge/SQLite-local-003B57.svg?logo=sqlite&logoColor=white)](https://www.sqlite.org/)
[![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-orange.svg?logo=swift)](https://developer.apple.com/xcode/swiftui/)
[![uv](https://img.shields.io/badge/managed%20by-uv-6C5CE7.svg)](https://docs.astral.sh/uv/)
[![Tests](https://img.shields.io/badge/tests-42%20passing-success.svg)](https://github.com/chgwyellow/personal_fin)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

Make your finances easier to understand.

Personal Finance is a privacy-first personal finance tool that helps you
understand your cash, investments, liabilities, and net worth over time. Your
financial data stays on your own device instead of being sent to a third-party
service.

## Current Features

- See total assets, liabilities, net worth, and financial indicators
- Add, edit, and delete assets and liabilities with user-defined subcategories
- Track Taiwan and U.S. stocks and ETFs while preserving original currencies
- Fetch market prices and exchange rates into local SQLite history tables
- Display portfolio market value, allocation, capital gains, and total gains
- Record dividends separately and include them in total portfolio P&L
- Manage dividend records with add, edit, and delete actions
- Manage recurring investment rules per holding, including multiple monthly
  execution days
- Record each recurring purchase with its actual date, shares, amount, and
  currency
- Keep all financial data locally on the Mac

## Built With

- Python 3.14+
- SQLite
- SwiftUI macOS desktop UI
- uv
- pytest
- Git / GitHub

## Architecture

- `src/`: existing Python data and analysis code. The current UI work does not
  modify these Python files.
- `Sources/PersonalFinanceApp/`: SwiftUI macOS application and local SQLite
  integration.
- `data/`: project data and reference files.
- `dist/FinTrack.app`: locally built macOS application bundle.

The SwiftUI app uses SQLite under:

```text
~/Library/Application Support/FinTrack/personal_finance.db
```

Market data currently comes from Yahoo Finance's public quote/search endpoints,
and exchange rates come from ExchangeRate-API. Results are cached locally; the
app refreshes data when relevant views load or after a holding is added.

## Getting Started

To build a local Apple Silicon app bundle:

```bash
swift build -c release
mkdir -p dist/FinTrack.app/Contents/MacOS
cp .build/arm64-apple-macosx/release/PersonalFinanceApp \
  dist/FinTrack.app/Contents/MacOS/PersonalFinanceApp
open dist/FinTrack.app
```

To create a release ZIP and SHA-256 checksum:

```bash
bash scripts/package-app.sh 0.1.1
```

See [`docs/releasing.md`](docs/releasing.md) for Universal builds, signing,
notarization, and data-safety checks.

For development, run:

```bash
swift run PersonalFinanceApp
```

The Python environment remains available separately through uv:

```bash
uv sync
```

## Project Information

- Product name: FinTrack
- Start date: 2026-09-02
- Current version: 0.1.1
- Development platform: macOS
- License: MIT License

## Known Limitations

- The app is macOS-only and has no signed installer or automatic updater yet.
- Market data availability depends on the external public APIs and their
  supported symbols.
- Recurring investment rules do not execute trades automatically; each actual
  purchase is entered manually.
- Exchange transactions and realized foreign-currency gains still require a
  future dedicated workflow.
