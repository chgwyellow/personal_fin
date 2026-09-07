"""Database operations and calculations for currency exchange rates."""

import sqlite3

from .database import connect_to_database


def get_latest_exchange_rate(
    base_currency: str,
    quote_currency: str,
) -> int | float | None:
    """Retrieve the latest stored exchange rate."""
    connection = connect_to_database()

    try:
        latest_rate = connection.execute(
            """
            SELECT rate
            FROM exchange_rates
            WHERE base_currency = ?
            AND quote_currency = ?
            ORDER BY observed_at DESC, id DESC
            LIMIT 1
            """,
            (
                base_currency,
                quote_currency,
            ),
        ).fetchone()
    finally:
        connection.close()

    if latest_rate is None:
        return None

    return latest_rate[0]


def create_exchange_rate(
    base_currency: str,
    quote_currency: str,
    rate: int | float,
    observed_at: str,
    source: str,
) -> int | None:
    """Store one currency exchange rate record."""
    connection = connect_to_database()

    try:
        cursor = connection.execute(
            """
            INSERT INTO exchange_rates
            (base_currency, quote_currency, rate, observed_at, source)
            VALUES (?, ?, ?, ?, ?)
            """,
            (base_currency, quote_currency, rate, observed_at, source),
        )
        connection.commit()

        created_id = cursor.lastrowid
    except sqlite3.Error:
        connection.rollback()
        raise
    finally:
        connection.close()

    return created_id


def convert_amount(
    amount: int | float,
    exchange_rate: int | float,
) -> int | float:
    """Convert an amount using the provided exchange rate."""

    return amount * exchange_rate
