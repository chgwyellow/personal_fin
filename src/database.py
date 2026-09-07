"""SQLite connection utilities for the personal finance application."""

import sqlite3
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DATABASE_PATH = PROJECT_ROOT / "data" / "personal_finance.db"


def connect_to_database() -> sqlite3.Connection:
    connection = sqlite3.connect(database=DATABASE_PATH)  # create it if not existing
    connection.execute("PRAGMA foreign_keys = ON")  # activate relationship
    return connection


if __name__ == "__main__":
    connection = connect_to_database()

    print("Database connection successful")

    connection.close()
