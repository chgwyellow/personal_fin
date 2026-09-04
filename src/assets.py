from src.database import connect_to_database


def create_asset(name, asset_group, category, currency, value):
    """Create one asset record in the local SQLite database.

    Args:
        name: User-facing name of the asset.
        asset_group: Balance-sheet group, such as ``liquid_asset``.
        category: More specific category, such as ``bank_account``.
        currency: Three-letter currency code, such as ``TWD`` or ``USD``.
        value: Current value in the asset's original currency.

    Returns:
        The ID of the newly created asset.

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

    Returns:
        A list of active asset records. If no active assets exist, an empty
        list is returned.
    """
    connection = connect_to_database()

    cursor = connection.execute(
        """
        SELECT id, name, asset_group, category, currency, value
        FROM assets
        WHERE is_active = 1
        ORDER BY id;
        """
    )

    assets = cursor.fetchall()  # get all results

    connection.close()

    return assets


def update_asset():
    """Update an existing asset in the database.

    This function is not implemented yet. Its future implementation should
    receive an asset ID and the fields to update.
    """
    pass


def delete_asset():
    """Delete or deactivate an existing asset in the database.

    This function is not implemented yet. Its future implementation should
    receive an asset ID and apply the project's deletion policy.
    """
    pass
