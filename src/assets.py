from src.database import connect_to_database


def create_asset(name, asset_group, category, currency, value):
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

    cursor = connection.execute(
        """
        INSERT INTO assets
        (name, asset_group, category, currency, value)
        VALUES (?, ?, ?, ?, ?);
        """,
        (name, asset_group, category, currency, value),
    )

    connection.commit()
    asset_id = cursor.lastrowid
    connection.close()

    return asset_id


def get_asset(asset_id):
    """Retrieve one asset from the database by its ID.

    Args:
        asset_id: The unique ID of the asset to retrieve.

    Returns:
        The matching asset record, or ``None`` if no asset is found.
    """
    connection = connect_to_database()

    cursor = connection.execute(
        """
        SELECT id, name, asset_group, category, currency, value
        FROM assets
        WHERE id = ?
        """,
        (asset_id,),
    )

    asset = cursor.fetchone()  # get the select result

    connection.close()

    return asset


def list_assets():
    """Retrieve all active assets from the database.

    This function is not implemented yet. Its future implementation should
    return the asset records in a collection that the caller can iterate over.
    """
    pass


def update_asset():
    """Update an existing asset in the database.

    This function is not implemented yet. Its future implementation should
    receive an asset identifier and the fields to update.
    """
    pass


def delete_asset():
    """Delete or deactivate an existing asset in the database.

    This function is not implemented yet. Its future implementation should
    receive an asset identifier and apply the project's deletion policy.
    """
    pass
