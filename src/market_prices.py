"""Queries for stored market price records."""

import sqlite3
from .database import connect_to_database


def get_latest_market_price(
    symbol: str,
    market: str,
) -> int | float | None:
    """Retrieve the latest stored market price for a symbol and market.

    Args:
        symbol: The security symbol.
        market: The market code, such as ``TW`` or ``US``.

    Returns:
        The latest stored price, or ``None`` if no price exists.
    """
    connection = connect_to_database()

    try:
        latest_price = connection.execute(
            """
            SELECT price
            FROM market_prices
            WHERE symbol = ?
            AND market = ?
            ORDER BY observed_at DESC, id DESC
            LIMIT 1
            """,
            (symbol, market),
        ).fetchone()
    finally:
        connection.close()

    if latest_price is None:
        return None

    return latest_price[0]


def create_market_price(
    symbol: str,
    market: str,
    price: int | float,
    currency: str,
    observed_at: str,
    source: str,
) -> int | None:
    """Store one market price record."""
    connection = connect_to_database()

    try:
        cursor = connection.execute(
            """
            INSERT INTO market_prices
            (symbol, market, price, currency, observed_at, source)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (symbol, market, price, currency, observed_at, source),
        )
        connection.commit()
        created_id = cursor.lastrowid
    except sqlite3.Error:
        connection.rollback()
        raise
    finally:
        connection.close()

    return created_id
