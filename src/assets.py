from src.database import connect_to_database


def add_asset(name, asset_group, category, currency, value):
    """Add one asset record to the local SQLite database.

    Args:
        name: User-facing name of the asset.
        asset_group: Balance-sheet group, such as ``liquid_asset``.
        category: More specific category, such as ``bank_account``.
        currency: Three-letter currency code, such as ``TWD`` or ``USD``.
        value: Current value in the asset's original currency.

    The function commits the new record and closes the database connection
    after the insert is complete.
    """
    connection = connect_to_database()

    connection.execute(
        """
        INSERT INTO assets
        (name, asset_group, category, currency, value)
        VALUES (?, ?, ?, ?, ?);
        """,
        (name, asset_group, category, currency, value),
    )

    connection.commit()
    connection.close()


