"""Database operations for dividend records."""

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
