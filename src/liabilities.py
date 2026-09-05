from .database import connect_to_database


def create_liability(
    name,
    liability_group,
    category,
    currency,
    balance,
    interest_rate=None,
    due_date=None,
):
    """Create one liability record in the local SQLite database.

    Args:
        name: User-facing name of the liability.
        liability_group: Liability group, either ``short_term`` or
            ``long_term``.
        category: More specific liability category, such as ``loan``.
        currency: Three-letter currency code, such as ``TWD`` or ``USD``.
        balance: Current balance in the liability's original currency.
        interest_rate: Optional annual interest rate.
        due_date: Optional repayment due date.

    Returns:
        The ID of the newly created liability.

    The function commits the new record and closes the database connection
    after the insert is complete.
    """
    connection = connect_to_database()

    liability = connection.execute(
        """
        INSERT INTO liabilities
        (name, liability_group, category, currency, balance, interest_rate, due_date)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        (name, liability_group, category, currency, balance, interest_rate, due_date),
    )

    connection.commit()
    connection.close()

    return liability.lastrowid


def get_liability(liability_id):
    """Retrieve one liability from the database by its ID.

    Args:
        liability_id: The unique ID of the liability to retrieve.

    Returns:
        The matching liability record, or ``None`` if no liability is found.
    """
    connection = connect_to_database()

    cursor = connection.execute(
        """
        SELECT id, name, liability_group, category, currency, balance, interest_rate, due_date
        FROM liabilities
        WHERE id = ?
        """,
        (liability_id,),
    )

    liability = cursor.fetchone()

    connection.close()

    return liability


def list_liabilities():
    """Retrieve all liabilities from the database.

    Returns:
        A list of liability records. If no liabilities exist, an empty list
        is returned.
    """
    connection = connect_to_database()

    cursor = connection.execute(
        """
        SELECT id, name, liability_group, category, currency, balance, interest_rate, due_date
        FROM liabilities
        ORDER BY id
        """
    )

    liabilities = cursor.fetchall()

    connection.close()# 

    return liabilities


def update_liability(liability_id, currency, balance):
    """Update the currency and balance of an existing liability.

    Args:
        liability_id: The unique ID of the liability to update.
        currency: The new three-letter currency code.
        balance: The new balance in the liability's original currency.

    Returns:
        ``True`` if a liability was found and updated; otherwise, ``False``.

    The function also updates the liability's ``updated_at`` timestamp.
    """
    connection = connect_to_database()

    cursor = connection.execute(
        """
        UPDATE liabilities
        SET currency = ?, balance = ?, updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
        """,
        (currency, balance, liability_id),
    )

    connection.commit()

    updated = cursor.rowcount > 0

    connection.close()

    return updated


def delete_liability(liability_id):
    """Permanently delete an existing liability from the database.

    Args:
        liability_id: The unique ID of the liability to delete.

    Returns:
        ``True`` if a liability was found and deleted; otherwise, ``False``.

    Unlike assets, liabilities do not currently have an ``is_active`` field,
    so this method removes the database record permanently.
    """
    connection = connect_to_database()

    cursor = connection.execute(
        """
        DELETE FROM liabilities
        WHERE id = ?
        """,
        (liability_id,),
    )

    connection.commit()

    deleted = cursor.rowcount > 0

    connection.close()

    return deleted
