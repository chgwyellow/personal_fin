from .database import connect_to_database


def get_total_assets_twd() -> int | float:
    """Sum the stored values of active assets denominated in TWD.

    Returns:
        The total value, or zero if no active TWD assets exist.
        Foreign-currency assets are excluded; no FX conversion is performed.
    """
    connection = connect_to_database()

    try:
        cursor = connection.execute(
            """
            SELECT COALESCE(SUM(value), 0)
            FROM assets
            WHERE is_active = 1
            AND currency = 'TWD'
            """
        )
        total_assets = cursor.fetchone()
    finally:
        connection.close()

    return total_assets[0]
