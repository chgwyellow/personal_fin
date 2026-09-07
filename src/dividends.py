"""Database operations for dividend records."""

import sqlite3
from .database import connect_to_database


def get_total_dividends_by_holding(
    holding_id: int,
) -> int | float:
    """Calculate total dividends received for one holding."""
    connection = connect_to_database()

    try:
        cursor = connection.execute(
            """
            SELECT COALESCE(SUM(amount), 0)
            FROM dividends
            WHERE holding_id = ?
            """,
            (holding_id,),
        )

        dividend = cursor.fetchone()
    finally:
        connection.close()

    return dividend[0]


def create_dividend(
    holding_id: int,
    received_date: str,
    amount: int | float,
    currency: str,
) -> int | None:
    """Create a dividend record for an investment holding."""
    connection = connect_to_database()

    try:
        cursor = connection.execute(
            """
            INSERT INTO dividends (holding_id, received_date, amount, currency)
            VALUES (?, ?, ?, ?)
            """,
            (holding_id, received_date, amount, currency),
        )
        connection.commit()
        dividend_id = cursor.lastrowid
    except sqlite3.Error:
        connection.rollback()
        raise
    finally:
        connection.close()

    return dividend_id


def list_dividends_by_holding(
    holding_id: int,
) -> list[tuple]:
    """List all dividend records for one investment holding."""
    connection = connect_to_database()

    try:
        dividend_details = connection.execute(
            """
            SELECT id, holding_id, received_date, amount, currency
            FROM dividends
            WHERE holding_id = ?
            ORDER BY received_date
            """,
            (holding_id,),
        ).fetchall()
    finally:
        connection.close()

    return dividend_details
