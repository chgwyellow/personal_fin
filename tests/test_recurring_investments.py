import sqlite3

from src.recurring_investments import create_recurring_investment


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
