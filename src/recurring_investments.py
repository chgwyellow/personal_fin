"""Database operations for recurring investment plans and executions."""

import sqlite3

from .database import connect_to_database


def create_recurring_investment(
    holding_id: int,
    planned_amount: int | float,
    currency: str,
    frequency: str,
    execution_day: int,
    start_date: str,
    end_date: str | None = None,
    notes: str | None = None,
) -> int | None:
    """Create a recurring investment plan for a holding."""
    connection = connect_to_database()

    try:
        cursor = connection.execute(
            """
            INSERT INTO recurring_investments
            (holding_id, planned_amount, currency, frequency, execution_day,
             start_date, end_date, notes)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                holding_id,
                planned_amount,
                currency,
                frequency,
                execution_day,
                start_date,
                end_date,
                notes,
            ),
        )
        connection.commit()

        created_id = cursor.lastrowid
    except sqlite3.Error:
        connection.rollback()
        raise
    finally:
        connection.close()

    return created_id


def list_recurring_investments_by_holding(
    holding_id: int,
) -> list[tuple]:
    """List recurring investment plans for one holding."""
    connection = connect_to_database()

    try:
        recurring_investments = connection.execute(
            """
            SELECT id, holding_id, planned_amount, currency,
            frequency, execution_day, start_date, end_date, notes
            FROM recurring_investments
            WHERE holding_id = ?
            ORDER BY start_date
            """,
            (holding_id,),
        ).fetchall()
    finally:
        connection.close()

    return recurring_investments


def update_recurring_investment(
    recurring_investment_id: int,
    planned_amount: int | float | None = None,
    currency: str | None = None,
    frequency: str | None = None,
    execution_day: int | None = None,
    start_date: str | None = None,
    end_date: str | None = None,
    notes: str | None = None,
) -> bool:
    """Update only the provided fields of a recurring investment plan.

    Args:
        recurring_investment_id: The ID of the plan to update.
        planned_amount: Optional new planned investment amount.
        currency: Optional new currency code.
        frequency: Optional new investment frequency.
        execution_day: Optional new execution day.
        start_date: Optional new start date.
        end_date: Optional new end date.
        notes: Optional new notes.

    Returns:
        True if a plan was updated, otherwise False.

    Raises:
        ValueError: If no fields are provided for update.
    """
    updates = {
        "planned_amount": planned_amount,
        "currency": currency,
        "frequency": frequency,
        "execution_day": execution_day,
        "start_date": start_date,
        "end_date": end_date,
        "notes": notes,
    }
    fields = [f"{field} = ?" for field, value in updates.items() if value is not None]
    values = [value for value in updates.values() if value is not None]

    if not fields:
        raise ValueError("At least one field is required for update.")

    connection = connect_to_database()

    try:
        cursor = connection.execute(
            f"""
            UPDATE recurring_investments
            SET {", ".join(fields)}
            WHERE id = ?
            """,
            (*values, recurring_investment_id),
        )
        connection.commit()
        updated = cursor.rowcount > 0
    except sqlite3.Error:
        connection.rollback()
        raise
    finally:
        connection.close()

    return updated


def create_recurring_investment_execution(
    recurring_investment_id: int | None,
    holding_id: int,
    execution_date: str,
    invested_amount: int | float,
    currency: str,
    shares_purchased: int | float,
    purchase_price: int | float,
    status: str = "confirmed",
    notes: str | None = None,
) -> int | None:
    """Create one actual recurring investment execution record.

    Args:
        recurring_investment_id: The related plan ID, if applicable.
        holding_id: The holding that received the purchased shares.
        execution_date: The date the investment was executed.
        invested_amount: The amount invested in the original currency.
        currency: The investment currency.
        shares_purchased: The number of shares or units purchased.
        purchase_price: The purchase price per share or unit.
        status: The execution status.
        notes: Optional notes about the execution.

    Returns:
        The ID of the newly created execution record.
    """
    connection = connect_to_database()

    try:
        cursor = connection.execute(
            """
            INSERT INTO recurring_investment_executions
            (recurring_investment_id, holding_id, execution_date, invested_amount,
             currency, shares_purchased, purchase_price, status, notes)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                recurring_investment_id,
                holding_id,
                execution_date,
                invested_amount,
                currency,
                shares_purchased,
                purchase_price,
                status,
                notes,
            ),
        )
        connection.commit()
        created_id = cursor.lastrowid
    except sqlite3.Error:
        connection.rollback()
        raise
    finally:
        connection.close()

    return created_id


def list_recurring_investment_executions_by_holding(
    holding_id: int,
) -> list[tuple]:
    """List execution records for one investment holding by date."""
    connection = connect_to_database()

    try:
        recurring_investment_executions = connection.execute(
            """
            SELECT id, recurring_investment_id, holding_id, execution_date,
                   invested_amount, currency, shares_purchased, purchase_price,
                   status, notes
            FROM recurring_investment_executions
            WHERE holding_id = ?
            ORDER BY execution_date, id
            """,
            (holding_id,),
        ).fetchall()
    finally:
        connection.close()

    return recurring_investment_executions


def delete_recurring_investment_execution(
    execution_id: int,
) -> bool:
    """Delete one recurring investment execution record by its ID."""
    connection = connect_to_database()

    try:
        cursor = connection.execute(
            """
            DELETE FROM recurring_investment_executions
            WHERE id = ?
            """,
            (execution_id,),
        )

        connection.commit()

        deleted = cursor.rowcount > 0
    except sqlite3.Error:
        connection.rollback()
        raise
    finally:
        connection.close()

    return deleted
