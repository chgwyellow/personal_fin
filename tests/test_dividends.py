import sqlite3

from src.dividends import get_total_dividends_by_holding


def create_test_connection() -> sqlite3.Connection:
    """Create an in-memory database containing the dividends table."""
    connection = sqlite3.connect(":memory:")
    connection.execute(
        """
        CREATE TABLE dividends (
            id INTEGER PRIMARY KEY,
            holding_id INTEGER NOT NULL,
            received_date TEXT NOT NULL,
            amount NUMERIC NOT NULL,
            currency TEXT NOT NULL
        )
        """
    )
    return connection


def test_get_total_dividends_by_holding(monkeypatch) -> None:
    """Test summing dividends for one holding."""
    connection = create_test_connection()
    connection.executemany(
        """
        INSERT INTO dividends
        (holding_id, received_date, amount, currency)
        VALUES (?, ?, ?, ?)
        """,
        [
            (1, "2026-01-01", 100, "NTD"),
            (1, "2026-02-01", 50, "NTD"),
            (2, "2026-03-01", 999, "NTD"),
        ],
    )
    connection.commit()
    monkeypatch.setattr("src.dividends.connect_to_database", lambda: connection)

    assert get_total_dividends_by_holding(1) == 150


def test_get_total_dividends_without_records(monkeypatch) -> None:
    """Test that a holding without dividends returns zero."""
    connection = create_test_connection()
    monkeypatch.setattr("src.dividends.connect_to_database", lambda: connection)

    assert get_total_dividends_by_holding(1) == 0
