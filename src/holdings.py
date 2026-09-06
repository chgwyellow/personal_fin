import sqlite3
from .database import connect_to_database


def create_holding(
    asset_id: int,
    symbol: str,
    security_name: str,
    market: str,
    currency: str,
    shares: int | float,
    total_cost: int | float,
) -> int | None:
    """Create one investment holding linked to an existing asset.

    Args:
        asset_id: The ID of the related asset.
        symbol: The security symbol, such as ``AAPL`` or ``2330.TW``.
        security_name: The display name of the stock or ETF.
        market: The market code, either ``TW`` or ``US``.
        currency: The security's original currency.
        shares: The number of shares or units held.
        total_cost: The total cost in the security's original currency.

    Returns:
        The ID of the newly created holding.
    """
    connection = connect_to_database()

    try:
        holding = connection.execute(
            """
            INSERT INTO holdings
            (asset_id, symbol, security_name, market, currency, shares, total_cost)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (asset_id, symbol, security_name, market, currency, shares, total_cost),
        )
        connection.commit()

    except sqlite3.Error:
        connection.rollback()
        raise
    finally:
        connection.close()

    return holding.lastrowid


def get_holding(holding_id: int) -> tuple | None:
    """Retrieve one investment holding by its ID."""
    connection = connect_to_database()

    try:
        cursor = connection.execute(
            """
            SELECT id, asset_id, symbol, security_name,
                market, currency, shares, total_cost
            FROM holdings
            WHERE id = ?
            """,
            (holding_id,),
        )

        holding = cursor.fetchone()
    finally:
        connection.close()

    return holding


def list_holdings() -> list[tuple]:
    """Retrieve all investment holdings from the database.

    Returns:
        A list of holding records. If no holdings exist, an empty list
        is returned.
    """
    connection = connect_to_database()

    try:
        cursor = connection.execute(
            """
            SELECT id, asset_id, symbol, security_name,
                market, currency, shares, total_cost
            FROM holdings
            ORDER BY id
            """
        )

        holdings = cursor.fetchall()
    finally:
        connection.close()

    return holdings


def update_holding(
    holding_id: int,
    shares: int | float,
    total_cost: int | float,
) -> bool:
    """Update the shares and total cost of an existing holding.

    Args:
        holding_id: The unique ID of the holding to update.
        shares: The new number of shares or units.
        total_cost: The new total cost in the security's original currency.

    Returns:
        ``True`` if a holding was found and updated; otherwise, ``False``.
    """
    connection = connect_to_database()

    try:
        cursor = connection.execute(
            """
            UPDATE holdings
            SET shares = ?,
                total_cost = ?,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
            """,
            (
                shares,
                total_cost,
                holding_id,
            ),
        )
        connection.commit()
        updated = cursor.rowcount > 0
    except sqlite3.Error:
        connection.rollback()
        raise
    finally:
        connection.close()

    return updated


def delete_holding(holding_id: int) -> bool:
    """Permanently delete an investment holding.

    Args:
        holding_id: The unique ID of the holding to delete.

    Returns:
        ``True`` if a holding was found and deleted; otherwise, ``False``.
    """
    connection = connect_to_database()

    try:
        cursor = connection.execute(
            """
            DELETE FROM holdings
            WHERE id = ?
            """,
            (holding_id,),
        )

        deleted = cursor.rowcount > 0
        connection.commit()
    except sqlite3.Error:
        connection.rollback()
        raise
    finally:
        connection.close()

    return deleted
