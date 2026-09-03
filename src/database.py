import sqlite3
from pathlib import Path

DATABASE_PATH = Path("data/personal_finance.db")


def connect_to_database():
    connection = sqlite3.connect(database=DATABASE_PATH)  # create it if not existing
    connection.execute("PRAGMA foreign_keys = ON")  # activate relationship
    return connection


if __name__ == "__main__":
    connection = connect_to_database()

    print("Database connection successful")

    connection.close()
