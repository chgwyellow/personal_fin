import sqlite3
from typing import Any
from .database import connect_to_database


def create_asset(name, asset_group, category, currency, value) -> int | None:
    """Create one asset record in the local SQLite database.

    Args:
        name: User-facing name of the asset.
        asset_group: Balance-sheet group, such as ``liquid_asset``.
        category: More specific category, such as ``bank_account``.
        currency: Three-letter currency code, such as ``NTD`` or ``USD``.
        value: Current value in the asset's original currency.

    Returns:
        The ID of the newly created asset.

    The function commits the new record and closes the database connection
    after the insert is complete.
    """
    connection = connect_to_database()

    try:
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
    except sqlite3.Error:
        connection.rollback()
        raise
    finally:
        connection.close()

    return asset_id


def get_asset(asset_id) -> tuple[Any, ...] | None:
    """Retrieve one asset from the database by its ID.

    Args:
        asset_id: The unique ID of the asset to retrieve.

    Returns:
        The matching asset record, or ``None`` if no asset is found.
    """
    connection = connect_to_database()

    try:
        cursor = connection.execute(
            """
            SELECT id, name, asset_group, category, currency, value
            FROM assets
            WHERE id = ?
            """,
            (asset_id,),
        )

        asset = cursor.fetchone()  # get the select result
    finally:
        connection.close()

    return asset


def list_assets() -> list[tuple[Any, ...]]:
    """Retrieve all active assets from the database.

    Returns:
        A list of active asset records. If no active assets exist, an empty
        list is returned.
    """
    connection = connect_to_database()

    try:
        cursor = connection.execute(
            """
            SELECT id, name, asset_group, category, currency, value
            FROM assets
            WHERE is_active = 1
            ORDER BY id;
            """
        )

        assets = cursor.fetchall()  # get all results
    finally:
        connection.close()

    return assets


def update_asset(asset_id, currency, value) -> bool:
    """Update the currency and value of an existing asset.

    Args:
        asset_id: The unique ID of the asset to update.
        currency: The new three-letter currency code.
        value: The new value in the asset's original currency.

    Returns:
        ``True`` if an asset was found and updated; otherwise, ``False``.

    The function also updates the asset's ``updated_at`` timestamp.
    """
    connection = connect_to_database()

    try:
        cursor = connection.execute(
            """
            UPDATE assets
            SET currency = ?, value = ?, updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
            """,
            (currency, value, asset_id),
        )

        connection.commit()
        updated = cursor.rowcount > 0
    except sqlite3.Error:
        connection.rollback()
        raise
    finally:
        connection.close()

    return updated


def delete_asset(asset_id) -> bool:
    """Deactivate an existing asset without removing its database record.

    Args:
        asset_id: The unique ID of the asset to deactivate.

    Returns:
        ``True`` if an active asset was found and deactivated; otherwise,
        ``False``.

    Deactivation sets ``is_active`` to ``0`` and preserves the asset's
    historical record. The asset will no longer be returned by
    :func:`list_assets`.
    """
    connection = connect_to_database()

    try:
        cursor = connection.execute(
            """
            UPDATE assets
            SET is_active = 0, updated_at = CURRENT_TIMESTAMP
            WHERE id = ? AND is_active = 1
            """,
            (asset_id,),
        )

        connection.commit()
        deleted = cursor.rowcount > 0
    except sqlite3.Error:
        connection.rollback()
        raise
    finally:
        connection.close()

    return deleted
