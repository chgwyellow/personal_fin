"""Database operations for recurring investment plans."""

import sqlite3

from .database import connect_to_database


def create_recurring_investment(
    holding_id: int,
    planned_amount: int | float,
    currency: str,
    frequency: str,
    execution_day: int,
    start_date: str,
    end_date: str | None = None,
    notes: str | None = None,
) -> int | None:
    """Create a recurring investment plan for a holding."""
    connection = connect_to_database()

    try:
        cursor = connection.execute(
            """
            INSERT INTO recurring_investments
            (holding_id, planned_amount, currency, frequency, execution_day,
             start_date, end_date, notes)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                holding_id,
                planned_amount,
                currency,
                frequency,
                execution_day,
                start_date,
                end_date,
                notes,
            ),
        )
        connection.commit()

        created_id = cursor.lastrowid
    except sqlite3.Error:
        connection.rollback()
        raise
    finally:
        connection.close()

    return created_id
