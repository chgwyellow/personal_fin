import sqlite3

from src.exchange_rates import (
    convert_amount,
    create_exchange_rate,
    get_latest_exchange_rate,
)


def create_test_connection(database: str) -> sqlite3.Connection:
    """Create a test database containing the exchange_rates table."""
    connection = sqlite3.connect(database)
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


def test_create_and_get_latest_exchange_rate(monkeypatch, tmp_path) -> None:
    """Test storing and retrieving the latest exchange rate."""
    database_path = tmp_path / "test_exchange_rates.db"
    setup_connection = create_test_connection(str(database_path))
    setup_connection.close()

    monkeypatch.setattr(
        "src.exchange_rates.connect_to_database",
        lambda: sqlite3.connect(database_path),
    )

    first_id = create_exchange_rate("USD", "NTD", 32.5, "2026-09-01", "test")
    second_id = create_exchange_rate("USD", "NTD", 32.8, "2026-09-02", "test")

    assert first_id is not None
    assert second_id is not None
    assert first_id != second_id
    assert get_latest_exchange_rate("USD", "NTD") == 32.8


def test_get_latest_exchange_rate_without_records(monkeypatch, tmp_path) -> None:
    """Test that a missing exchange rate returns None."""
    database_path = tmp_path / "test_exchange_rates.db"
    setup_connection = create_test_connection(str(database_path))
    setup_connection.close()

    monkeypatch.setattr(
        "src.exchange_rates.connect_to_database",
        lambda: sqlite3.connect(database_path),
    )

    assert get_latest_exchange_rate("USD", "NTD") is None


def test_convert_amount() -> None:
    """Test converting an amount with an exchange rate."""
    assert convert_amount(100, 32.5) == 3250
    assert convert_amount(0, 32.5) == 0
