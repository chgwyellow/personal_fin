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

## Product Features

- See total assets, liabilities, net worth, and free cash flow at a glance
- Organize cash, stocks, ETFs, and other assets clearly
- Track Taiwan and U.S. investments while keeping portfolio values in their
  original currencies
- Convert balance-sheet values with exchange rates and view them in NTD
- Record dividends and distinguish capital gains from total gains
- Manage recurring investment plans and their individual executions
- Keep market-price and exchange-rate history for review and recovery
- Store everything locally with SQLite for speed, simplicity, and privacy

## Built With

- Python 3.14+
- SQLite
- SwiftUI macOS desktop UI
- uv
- pytest
- Git / GitHub

## Getting Started

The project is currently under development and does not yet provide a desktop
installer. Clone the repository and set up the environment with uv:

```bash
git clone https://github.com/chgwyellow/personal_fin.git
cd personal_fin
uv sync
swift run PersonalFinanceApp
```

The first UI version is a SwiftUI visual prototype with sample values. Database
integration and interactive data entry will be connected in later iterations.

## Project Information

- Start date: 2026-09-02
- Current version: 0.1.0
- Development platform: macOS
- License: MIT License

Automatic market-data integration is currently in development.
