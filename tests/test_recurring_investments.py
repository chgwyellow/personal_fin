import sqlite3

import pytest

from src.recurring_investments import (
    create_recurring_investment,
    create_recurring_investment_execution,
    update_recurring_investment,
)


def create_test_connection(database: str) -> sqlite3.Connection:
    """Create a test database containing recurring investment plans."""
    connection = sqlite3.connect(database)
    connection.execute(
        """
        CREATE TABLE recurring_investments (
            id INTEGER PRIMARY KEY,
            holding_id INTEGER NOT NULL,
            planned_amount NUMERIC NOT NULL,
            currency TEXT NOT NULL,
            frequency TEXT NOT NULL,
            execution_day INTEGER NOT NULL,
            start_date TEXT NOT NULL,
            end_date TEXT,
            notes TEXT
        )
        """
    )
    connection.execute(
        """
        CREATE TABLE recurring_investment_executions (
            id INTEGER PRIMARY KEY,
            recurring_investment_id INTEGER,
            holding_id INTEGER NOT NULL,
            execution_date TEXT NOT NULL,
            invested_amount NUMERIC NOT NULL,
            currency TEXT NOT NULL,
            shares_purchased NUMERIC NOT NULL,
            purchase_price NUMERIC NOT NULL,
            status TEXT NOT NULL,
            notes TEXT
        )
        """
    )
    connection.commit()
    return connection


def test_create_recurring_investment(monkeypatch, tmp_path) -> None:
    """Test creating a recurring investment plan."""
    database_path = tmp_path / "test_recurring_investments.db"
    setup_connection = create_test_connection(str(database_path))
    setup_connection.close()

    monkeypatch.setattr(
        "src.recurring_investments.connect_to_database",
        lambda: sqlite3.connect(database_path),
    )

    recurring_id = create_recurring_investment(
        holding_id=1,
        planned_amount=5000,
        currency="NTD",
        frequency="monthly",
        execution_day=15,
        start_date="2026-09-01",
        end_date=None,
        notes="Test plan",
    )

    connection = sqlite3.connect(database_path)
    plan = connection.execute(
        """
        SELECT holding_id, planned_amount, currency, frequency,
               execution_day, start_date, end_date, notes
        FROM recurring_investments
        WHERE id = ?
        """,
        (recurring_id,),
    ).fetchone()
    connection.close()

    assert recurring_id is not None
    assert plan == (1, 5000, "NTD", "monthly", 15, "2026-09-01", None, "Test plan")


def test_update_recurring_investment_partial_field(monkeypatch, tmp_path) -> None:
    """Test updating one field while preserving the other fields."""
    database_path = tmp_path / "test_recurring_investments.db"
    setup_connection = create_test_connection(str(database_path))
    setup_connection.execute(
        """
        INSERT INTO recurring_investments
        (id, holding_id, planned_amount, currency, frequency,
         execution_day, start_date, end_date, notes)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (1, 1, 5000, "NTD", "monthly", 15, "2026-09-01", None, "Test plan"),
    )
    setup_connection.commit()
    setup_connection.close()
    monkeypatch.setattr(
        "src.recurring_investments.connect_to_database",
        lambda: sqlite3.connect(database_path),
    )

    assert update_recurring_investment(1, frequency="weekly") is True

    connection = sqlite3.connect(database_path)
    plan = connection.execute(
        "SELECT planned_amount, frequency FROM recurring_investments WHERE id = 1"
    ).fetchone()
    connection.close()

    assert plan == (5000, "weekly")


def test_update_missing_recurring_investment(monkeypatch, tmp_path) -> None:
    """Test updating a recurring investment plan that does not exist."""
    database_path = tmp_path / "test_recurring_investments.db"
    setup_connection = create_test_connection(str(database_path))
    setup_connection.close()
    monkeypatch.setattr(
        "src.recurring_investments.connect_to_database",
        lambda: sqlite3.connect(database_path),
    )

    assert update_recurring_investment(999, frequency="weekly") is False


def test_update_recurring_investment_without_fields() -> None:
    """Test that an update requires at least one field."""
    with pytest.raises(ValueError, match="At least one field"):
        update_recurring_investment(1)


def test_create_recurring_investment_execution(monkeypatch, tmp_path) -> None:
    """Test creating one recurring investment execution record."""
    database_path = tmp_path / "test_recurring_investments.db"
    setup_connection = create_test_connection(str(database_path))
    setup_connection.close()
    monkeypatch.setattr(
        "src.recurring_investments.connect_to_database",
        lambda: sqlite3.connect(database_path),
    )

    execution_id = create_recurring_investment_execution(
        recurring_investment_id=1,
        holding_id=2,
        execution_date="2026-09-07",
        invested_amount=5000,
        currency="NTD",
        shares_purchased=10,
        purchase_price=500,
        status="confirmed",
        notes="Test execution",
    )

    connection = sqlite3.connect(database_path)
    execution = connection.execute(
        """
        SELECT recurring_investment_id, holding_id, execution_date,
               invested_amount, currency, shares_purchased, purchase_price,
               status, notes
        FROM recurring_investment_executions
        WHERE id = ?
        """,
        (execution_id,),
    ).fetchone()
    connection.close()

    assert execution_id is not None
    assert execution == (
        1,
        2,
        "2026-09-07",
        5000,
        "NTD",
        10,
        500,
        "confirmed",
        "Test execution",
    )
