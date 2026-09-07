import sqlite3

import pytest

from src.dividends import (
    create_dividend,
    get_total_dividends_by_holding,
    list_dividends_by_holding,
)


def create_test_connection(
    database: str = ":memory:",
) -> sqlite3.Connection:
    """Create a test database containing the holdings and dividends tables."""
    connection = sqlite3.connect(database)
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


def test_create_dividend(monkeypatch, tmp_path) -> None:
    """Test creating a dividend record."""
    database_path = tmp_path / "test_dividends.db"
    setup_connection = create_test_connection(str(database_path))
    setup_connection.commit()
    setup_connection.close()
    monkeypatch.setattr(
        "src.dividends.connect_to_database",
        lambda: sqlite3.connect(database_path),
    )

    dividend_id = create_dividend(1, "2026-04-01", 150, "NTD")

    connection = sqlite3.connect(database_path)
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


def test_list_dividends_by_holding(monkeypatch) -> None:
    """Test listing dividends in received-date order."""
    connection = create_test_connection()
    connection.executemany(
        """
        INSERT INTO dividends
        (holding_id, received_date, amount, currency)
        VALUES (?, ?, ?, ?)
        """,
        [
            (1, "2026-06-01", 200, "NTD"),
            (1, "2026-04-01", 100, "NTD"),
            (2, "2026-05-01", 999, "NTD"),
        ],
    )
    connection.commit()
    monkeypatch.setattr("src.dividends.connect_to_database", lambda: connection)

    result = list_dividends_by_holding(1)

    assert result == [
        (2, 1, "2026-04-01", 100, "NTD"),
        (1, 1, "2026-06-01", 200, "NTD"),
    ]
