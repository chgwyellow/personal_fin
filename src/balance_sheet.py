from .database import connect_to_database


def get_total_assets_ntd() -> int | float:
    """Sum the stored values of active assets denominated in NTD.

    Returns:
        The total value, or zero if no active NTD assets exist.
        Foreign-currency assets are excluded; no FX conversion is performed.
    """
    connection = connect_to_database()

    try:
        cursor = connection.execute(
            """
            SELECT COALESCE(SUM(value), 0)
            FROM assets
            WHERE is_active = 1
            AND currency = 'NTD'
            """
        )
        total_assets = cursor.fetchone()
    finally:
        connection.close()

    return total_assets[0]


def get_total_liabilities_ntd() -> int | float:
    """Return the sum of NTD liability balances, or zero when none exist."""
    connection = connect_to_database()

    try:
        cursor = connection.execute(
            """
            SELECT COALESCE(SUM(balance), 0)
            FROM liabilities
            WHERE currency = 'NTD'
            """
        )
        total_liabilities = cursor.fetchone()
    finally:
        connection.close()

    return total_liabilities[0]


def get_net_worth_ntd() -> int | float:
    """Return NTD-only assets minus liabilities, excluding foreign currencies."""
    net_worth_ntd = get_total_assets_ntd() - get_total_liabilities_ntd()

    return net_worth_ntd


def get_assets_total_by_group_ntd(asset_group: str) -> int | float:
    connection = connect_to_database()

    try:
        cursor = connection.execute(
            """
            SELECT COALESCE(SUM(value), 0)
            FROM assets
            WHERE is_active = 1
            AND currency = 'NTD'
            AND asset_group = ?
            """,
            (asset_group,),
        )
        grouped_asset = cursor.fetchone()
    finally:
        connection.close()

    return grouped_asset[0]
