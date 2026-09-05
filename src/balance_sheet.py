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
    """Sum active NTD asset values for the specified group.

    Args:
        asset_group: The group to sum, such as ``liquid_asset``,
            ``liquid_investment``, or ``other_asset``.

    Returns:
        The total stored value, or zero if no matching assets exist.
        Inactive and foreign-currency assets are excluded.
        No FX conversion is performed.
    """
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


def get_liabilities_total_by_group_ntd(
    liability_group: str,
) -> int | float:
    """Sum NTD liability balances for the specified group.

    Args:
        liability_group: The group to sum, either ``short_term`` or
            ``long_term``.

    Returns:
        The total balance, or zero if no matching liabilities exist.
        Foreign-currency liabilities are excluded; no FX conversion
        is performed.
    """
    connection = connect_to_database()

    try:
        cursor = connection.execute(
            """
            SELECT COALESCE(SUM(balance), 0)
            FROM liabilities
            WHERE currency = 'NTD'
            AND liability_group = ?
            """,
            (liability_group,),
        )
        grouped_liability = cursor.fetchone()
    finally:
        connection.close()

    return grouped_liability[0]


def get_liability_ratio_ntd() -> float | None:
    """Calculate the liability-to-asset ratio using NTD-only values.

    Returns:
        Total NTD liabilities divided by total active NTD assets.
        Returns None when total assets are zero.
        Foreign-currency assets and liabilities are excluded.
    """
    total_assets = get_total_assets_ntd()

    if total_assets == 0:
        return None

    total_liabilities = get_total_liabilities_ntd()

    return total_liabilities / total_assets


def get_equity_multiplier_ntd() -> float | None:
    """Calculate the equity multiplier using NTD-only values.

    Returns:
        Total active NTD assets divided by NTD net worth.
        Returns None when net worth is zero.
        Foreign-currency assets and liabilities are excluded.
    """
    net_worth = get_net_worth_ntd()

    if net_worth == 0:
        return None

    total_assets = get_total_assets_ntd()

    return total_assets / net_worth


def get_free_cash_flow_ntd() -> int | float:
    """Calculate the project's custom free-cash-flow metric in NTD.

    Returns:
        NTD net worth minus active NTD assets in the ``other_asset`` group.
        The result may be negative. Foreign currencies are excluded.

    This project-specific metric does not measure cash flows over a period.
    """
    net_worth = get_net_worth_ntd()
    fixed_asset = get_assets_total_by_group_ntd("other_asset")

    return net_worth - fixed_asset


def get_cash_ratio_ntd() -> float | None:
    """Calculate the cash ratio using NTD-only values.

    Returns:
        Active NTD liquid assets divided by total NTD liabilities.
        Returns None when total liabilities are zero.
        Foreign currencies are excluded.
    """
    liquid_asset = get_assets_total_by_group_ntd("liquid_asset")
    liabilities = get_total_liabilities_ntd()

    if liabilities == 0:
        return None

    return liquid_asset / liabilities


def calculate_net_worth_growth_rate(
    current_net_worth: int | float,
    previous_net_worth: int | float,
) -> float | None:
    """Calculate the change in net worth relative to the previous magnitude.

    Args:
        current_net_worth: Net worth for the current period.
        previous_net_worth: Net worth for the previous period.
            Both values must use the same currency.

    Returns:
        (Current net worth - previous net worth) / abs(previous net worth).
        Positive values indicate improvement, including from negative net worth.
        Returns None when previous net worth is zero.
    """
    if previous_net_worth == 0:
        return None

    return (current_net_worth - previous_net_worth) / abs(previous_net_worth)


def get_asset_group_ratio_ntd(asset_group: str) -> float | None:
    """Calculate an asset group's share of total active NTD assets.

    Args:
        asset_group: The group to measure, such as ``liquid_asset``,
            ``liquid_investment``, or ``other_asset``.

    Returns:
        The group's NTD value divided by total active NTD assets.
        Returns None when total assets are zero.
        Returns zero if the group has no assets but total assets are positive.
        Inactive and foreign-currency assets are excluded.
    """
    total_assets = get_total_assets_ntd()

    if total_assets == 0:
        return None

    grouped_asset = get_assets_total_by_group_ntd(asset_group)

    return grouped_asset / total_assets


def get_liability_group_ratio_ntd(
    liability_group: str,
) -> float | None:
    """Calculate a liability group's share of total NTD liabilities.

    Args:
        liability_group: The group to measure, either ``short_term``
            or ``long_term``.

    Returns:
        The group's NTD balance divided by total NTD liabilities.
        Returns None when total liabilities are zero.
        Returns zero if the group has no liabilities but the total is positive.
        Foreign-currency liabilities are excluded.
    """
    total_liabilities = get_total_liabilities_ntd()

    if total_liabilities == 0:
        return None

    grouped_liability = get_liabilities_total_by_group_ntd(liability_group)

    return grouped_liability / total_liabilities


def get_balance_sheet_summary_ntd() -> dict[str, int | float | None]:
    """Build a balance-sheet summary using NTD-only values.

    Returns:
        A dictionary containing:
            total_assets: Total active NTD asset value.
            total_liabilities: Total NTD liability balance.
            net_worth: Total assets minus total liabilities.
            liability_ratio: Liabilities divided by assets, or None
                when total assets are zero.
            liquid_assets: Total active NTD liquid asset value.
            liquid_investments: Total active NTD liquid investment value.
            other_assets: Total active NTD other asset value.

        Foreign-currency assets and liabilities are excluded.
    """

    total_assets = get_total_assets_ntd()
    total_liabilities = get_total_liabilities_ntd()

    liability_ratio = None
    if total_assets != 0:
        liability_ratio = total_liabilities / total_assets

    return {
        "total_assets": total_assets,
        "total_liabilities": total_liabilities,
        "net_worth": total_assets - total_liabilities,
        "liability_ratio": liability_ratio,
        "liquid_assets": get_assets_total_by_group_ntd("liquid_asset"),
        "liquid_investments": get_assets_total_by_group_ntd("liquid_investment"),
        "other_assets": get_assets_total_by_group_ntd("other_asset"),
    }
