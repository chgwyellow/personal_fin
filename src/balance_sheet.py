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


def get_total_liabilities_twd() -> int | float:
    connection = connect_to_database()

    try:
        cursor = connection.execute(
            """
            SELECT COALESCE(SUM(balance), 0)
            FROM liabilities
            WHERE currency = 'TWD'
            """
        )
        total_liabilities = cursor.fetchone()
    finally:
        connection.close()

    return total_liabilities[0]


def get_net_worth_twd() -> int | float:
    net_worth_ntd = get_total_assets_twd() - get_total_liabilities_twd()

    return net_worth_ntd
