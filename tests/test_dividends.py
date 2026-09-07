import sqlite3

import pytest

from src.dividends import create_dividend, get_total_dividends_by_holding


def create_test_connection() -> sqlite3.Connection:
    """Create an in-memory database containing the dividends table."""
    connection = sqlite3.connect(":memory:")
    connection.execute("PRAGMA foreign_keys = ON")
    connection.execute(
        """
        CREATE TABLE holdings (
            id INTEGER PRIMARY KEY
        )
        """
    )
    connection.executemany(
        "INSERT INTO holdings (id) VALUES (?)",
        [(1,), (2,)],
    )
    connection.execute(
        """
        CREATE TABLE dividends (
            id INTEGER PRIMARY KEY,
            holding_id INTEGER NOT NULL,
            received_date TEXT NOT NULL,
            amount NUMERIC NOT NULL,
            currency TEXT NOT NULL,
            FOREIGN KEY (holding_id) REFERENCES holdings(id)
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


def test_create_dividend(monkeypatch) -> None:
    """Test creating a dividend record."""
    connection = create_test_connection()

    class TestConnection:
        """Keep the test connection open for post-insert verification."""

        def execute(self, *args):
            return connection.execute(*args)

        def commit(self):
            connection.commit()

        def rollback(self):
            connection.rollback()

        def close(self):
            pass

    test_connection = TestConnection()
    monkeypatch.setattr(
        "src.dividends.connect_to_database",
        lambda: test_connection,
    )

    dividend_id = create_dividend(1, "2026-04-01", 150, "NTD")

    dividend = connection.execute(
        """
        SELECT holding_id, received_date, amount, currency
        FROM dividends
        WHERE id = ?
        """,
        (dividend_id,),
    ).fetchone()

    assert dividend_id is not None
    assert dividend == (1, "2026-04-01", 150, "NTD")
    connection.close()


def test_create_dividend_with_invalid_holding(monkeypatch) -> None:
    """Test that an invalid holding ID raises a database error."""
    connection = create_test_connection()
    monkeypatch.setattr("src.dividends.connect_to_database", lambda: connection)

    with pytest.raises(sqlite3.IntegrityError):
        create_dividend(999, "2026-04-01", 150, "NTD")
