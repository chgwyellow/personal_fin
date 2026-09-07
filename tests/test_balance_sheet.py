import sqlite3

import pytest

from src.balance_sheet import get_total_assets_ntd


def create_test_database(database: str) -> sqlite3.Connection:
    """Create tables needed to test total asset calculation."""
    connection = sqlite3.connect(database)
    connection.execute(
        """
        CREATE TABLE assets (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            asset_group TEXT NOT NULL,
            category TEXT NOT NULL,
            currency TEXT NOT NULL,
            value NUMERIC NOT NULL,
            is_active INTEGER NOT NULL
        )
        """
    )
    connection.execute(
        """
        CREATE TABLE exchange_rates (
            id INTEGER PRIMARY KEY,
            base_currency TEXT NOT NULL,
            quote_currency TEXT NOT NULL,
            rate NUMERIC NOT NULL,
            observed_at TEXT NOT NULL,
            source TEXT NOT NULL
        )
        """
    )
    connection.commit()
    return connection


def test_get_total_assets_ntd_with_usd_assets(monkeypatch, tmp_path) -> None:
    """Test converting USD assets to NTD in total assets."""
    database_path = tmp_path / "test_balance_sheet.db"
    setup_connection = create_test_database(str(database_path))
    setup_connection.executemany(
        """
        INSERT INTO assets
        (name, asset_group, category, currency, value, is_active)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        [
            ("NTD asset", "liquid_asset", "cash", "NTD", 1000, 1),
            ("USD asset", "liquid_investment", "stock", "USD", 100, 1),
        ],
    )
    setup_connection.execute(
        """
        INSERT INTO exchange_rates
        (base_currency, quote_currency, rate, observed_at, source)
        VALUES (?, ?, ?, ?, ?)
        """,
        ("USD", "NTD", 32.5, "2026-09-01", "test"),
    )
    setup_connection.commit()
    setup_connection.close()

    monkeypatch.setattr(
        "src.balance_sheet.connect_to_database",
        lambda: sqlite3.connect(database_path),
    )
    monkeypatch.setattr(
        "src.exchange_rates.connect_to_database",
        lambda: sqlite3.connect(database_path),
    )

    assert get_total_assets_ntd() == 4250


def test_get_total_assets_ntd_without_exchange_rate(monkeypatch, tmp_path) -> None:
    """Test missing exchange rates raise a clear error."""
    database_path = tmp_path / "test_balance_sheet.db"
    setup_connection = create_test_database(str(database_path))
    setup_connection.execute(
        """
        INSERT INTO assets
        (name, asset_group, category, currency, value, is_active)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        ("USD asset", "liquid_investment", "stock", "USD", 100, 1),
    )
    setup_connection.commit()
    setup_connection.close()

    monkeypatch.setattr(
        "src.balance_sheet.connect_to_database",
        lambda: sqlite3.connect(database_path),
    )
    monkeypatch.setattr(
        "src.exchange_rates.connect_to_database",
        lambda: sqlite3.connect(database_path),
    )

    with pytest.raises(ValueError, match="Missing exchange rate"):
        get_total_assets_ntd()
