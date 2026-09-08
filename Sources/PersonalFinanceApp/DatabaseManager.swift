import CSQLite
import Foundation

/// Handles the local SQLite database used by the FinTrack macOS app.
final class DatabaseManager {
    enum DatabaseError: LocalizedError {
        case openFailed(String)
        case queryFailed(String)

        var errorDescription: String? {
            switch self {
            case .openFailed(let message):
                return "Unable to open database: \(message)"
            case .queryFailed(let message):
                return "Database query failed: \(message)"
            }
        }
    }

    private var database: OpaquePointer?

    /// Opens FinTrack's database and creates its initial tables if needed.
    init() throws {
        let fileManager = FileManager.default
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent("FinTrack", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let databaseURL = directory.appendingPathComponent("personal_finance.db")
        if sqlite3_open(databaseURL.path, &database) != SQLITE_OK {
            let message = databaseMessage
            sqlite3_close(database)
            database = nil
            throw DatabaseError.openFailed(message)
        }

        do {
            try execute(schemaSQL)
        } catch {
            sqlite3_close(database)
            database = nil
            throw error
        }
    }

    deinit {
        sqlite3_close(database)
    }

    /// Executes a SQL statement that does not return rows.
    func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)

        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? databaseMessage
            sqlite3_free(errorMessage)
            throw DatabaseError.queryFailed(message)
        }
    }

    private var databaseMessage: String {
        guard let database else { return "Unknown SQLite error" }
        return String(cString: sqlite3_errmsg(database))
    }

    private let schemaSQL = """
    PRAGMA foreign_keys = ON;

    CREATE TABLE IF NOT EXISTS assets (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        asset_group TEXT NOT NULL,
        category TEXT NOT NULL,
        currency TEXT NOT NULL,
        value NUMERIC NOT NULL DEFAULT 0,
        notes TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS liabilities (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        liability_group TEXT NOT NULL,
        category TEXT NOT NULL,
        currency TEXT NOT NULL,
        balance NUMERIC NOT NULL DEFAULT 0,
        interest_rate NUMERIC,
        due_date TEXT,
        notes TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    );
    """
}
