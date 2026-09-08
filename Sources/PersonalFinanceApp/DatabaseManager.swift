import CSQLite
import Foundation

/// Handles the local SQLite database used by the FinTrack macOS app.
final class DatabaseManager {
    struct AssetTotals {
        let liquidAsset: Double
        let liquidInvestment: Double
        let otherAsset: Double

        var total: Double {
            liquidAsset + liquidInvestment + otherAsset
        }
    }

    struct LiabilityTotals {
        let shortTerm: Double
        let longTerm: Double

        var total: Double {
            shortTerm + longTerm
        }
    }

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
            try addNTDValueColumnIfNeeded()
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

    /// Inserts one asset and returns the generated database ID.
    func createAsset(
        name: String,
        assetGroup: String,
        category: String,
        currency: String,
        value: Double,
        ntdValue: Double
    ) throws -> Int64 {
        let sql = """
        INSERT INTO assets (name, asset_group, category, currency, value, ntd_value)
        VALUES (?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(databaseMessage)
        }

        let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, name, -1, transientDestructor)
        sqlite3_bind_text(statement, 2, assetGroup, -1, transientDestructor)
        sqlite3_bind_text(statement, 3, category, -1, transientDestructor)
        sqlite3_bind_text(statement, 4, currency, -1, transientDestructor)
        sqlite3_bind_double(statement, 5, value)
        sqlite3_bind_double(statement, 6, ntdValue)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.queryFailed(databaseMessage)
        }

        return sqlite3_last_insert_rowid(database)
    }

    /// Returns asset totals in NTD, grouped by the balance-sheet asset group.
    func assetTotals() throws -> AssetTotals {
        let sql = """
        SELECT asset_group, COALESCE(SUM(ntd_value), 0)
        FROM assets
        WHERE is_active = 1
        GROUP BY asset_group;
        """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(databaseMessage)
        }

        var totals: [String: Double] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let groupPointer = sqlite3_column_text(statement, 0) else { continue }
            let group = String(cString: groupPointer)
            totals[group] = sqlite3_column_double(statement, 1)
        }

        return AssetTotals(
            liquidAsset: totals["liquid_asset"] ?? 0,
            liquidInvestment: totals["liquid_investment"] ?? 0,
            otherAsset: totals["other_asset"] ?? 0
        )
    }

    /// Inserts one liability and returns the generated database ID.
    func createLiability(
        name: String,
        liabilityGroup: String,
        category: String,
        currency: String,
        balance: Double,
        interestRate: Double?
    ) throws -> Int64 {
        let sql = """
        INSERT INTO liabilities
            (name, liability_group, category, currency, balance, interest_rate)
        VALUES (?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(databaseMessage)
        }

        let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, name, -1, transientDestructor)
        sqlite3_bind_text(statement, 2, liabilityGroup, -1, transientDestructor)
        sqlite3_bind_text(statement, 3, category, -1, transientDestructor)
        sqlite3_bind_text(statement, 4, currency, -1, transientDestructor)
        sqlite3_bind_double(statement, 5, balance)
        if let interestRate {
            sqlite3_bind_double(statement, 6, interestRate)
        } else {
            sqlite3_bind_null(statement, 6)
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.queryFailed(databaseMessage)
        }

        return sqlite3_last_insert_rowid(database)
    }

    /// Returns liability totals grouped by short-term and long-term debt.
    func liabilityTotals() throws -> LiabilityTotals {
        let sql = """
        SELECT liability_group, COALESCE(SUM(balance), 0)
        FROM liabilities
        WHERE currency = 'NTD'
        GROUP BY liability_group;
        """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(databaseMessage)
        }

        var totals: [String: Double] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let groupPointer = sqlite3_column_text(statement, 0) else { continue }
            let group = String(cString: groupPointer)
            totals[group] = sqlite3_column_double(statement, 1)
        }

        return LiabilityTotals(
            shortTerm: totals["short_term"] ?? 0,
            longTerm: totals["long_term"] ?? 0
        )
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
        ntd_value NUMERIC NOT NULL DEFAULT 0,
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

    private func addNTDValueColumnIfNeeded() throws {
        do {
            try execute("ALTER TABLE assets ADD COLUMN ntd_value NUMERIC NOT NULL DEFAULT 0;")
        } catch DatabaseError.queryFailed(let message) where message.contains("duplicate column name") {
            // The column already exists in databases created by newer versions.
        }
    }
}
