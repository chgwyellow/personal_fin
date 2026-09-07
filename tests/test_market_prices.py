import sqlite3

from src.market_prices import create_market_price, get_latest_market_price


def create_test_connection(database: str) -> sqlite3.Connection:
    """Create a test database containing the market_prices table."""
    connection = sqlite3.connect(database)
    connection.execute(
        """
        CREATE TABLE market_prices (
            id INTEGER PRIMARY KEY,
            symbol TEXT NOT NULL,
            market TEXT NOT NULL,
            price NUMERIC NOT NULL,
            currency TEXT NOT NULL,
            observed_at TEXT NOT NULL,
            source TEXT NOT NULL
        )
        """
    )
    connection.commit()
    return connection


def test_create_multiple_market_prices(monkeypatch, tmp_path) -> None:
    """Test storing multiple prices for the same symbol."""
    database_path = tmp_path / "test_market_prices.db"
    setup_connection = create_test_connection(str(database_path))
    setup_connection.close()

    monkeypatch.setattr(
        "src.market_prices.connect_to_database",
        lambda: sqlite3.connect(database_path),
    )

    first_id = create_market_price(
        "AAPL", "US", 180, "USD", "2026-09-01T10:00:00", "test"
    )
    second_id = create_market_price(
        "AAPL", "US", 182, "USD", "2026-09-02T10:00:00", "test"
    )

    assert first_id is not None
    assert second_id is not None
    assert first_id != second_id
    assert get_latest_market_price("AAPL") == 182
