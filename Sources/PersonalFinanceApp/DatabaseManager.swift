import CSQLite
import Foundation

/// Handles the local SQLite database used by the FinTrack macOS app.
final class DatabaseManager {
    struct AssetTotals {
        let liquidAsset: Double
        let liquidInvestment: Double
        let longTermInvestment: Double
        let otherAsset: Double

        var total: Double {
            liquidAsset + liquidInvestment + longTermInvestment + otherAsset
        }
    }

    struct LiabilityTotals {
        let shortTerm: Double
        let longTerm: Double

        var total: Double {
            shortTerm + longTerm
        }
    }

    struct AssetRecord: Identifiable {
        let id: Int64
        let name: String
        let assetGroup: String
        let category: String
        let currency: String
        let value: Double
        let ntdValue: Double
    }

    struct LiabilityRecord: Identifiable {
        let id: Int64
        let name: String
        let liabilityGroup: String
        let category: String
        let currency: String
        let balance: Double
        let interestRate: Double?
    }

    struct Snapshot {
        let date: String
        let totalAssets: Double
        let totalLiabilities: Double
        let netWorth: Double
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
            try addHoldingsClassificationColumnsIfNeeded()
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
            longTermInvestment: totals["long_term_investment"] ?? 0,
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

    /// Returns all active asset records for display in the Overview.
    func listAssets() throws -> [AssetRecord] {
        let sql = """
        SELECT id, name, asset_group, category, currency, value, ntd_value
        FROM assets
        WHERE is_active = 1
        ORDER BY name COLLATE NOCASE DESC;
        """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(databaseMessage)
        }

        var records: [AssetRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            records.append(AssetRecord(
                id: sqlite3_column_int64(statement, 0),
                name: String(cString: sqlite3_column_text(statement, 1)),
                assetGroup: String(cString: sqlite3_column_text(statement, 2)),
                category: String(cString: sqlite3_column_text(statement, 3)),
                currency: String(cString: sqlite3_column_text(statement, 4)),
                value: sqlite3_column_double(statement, 5),
                ntdValue: sqlite3_column_double(statement, 6)
            ))
        }
        return records
    }

    /// Returns all liability records for display in the Overview.
    func listLiabilities() throws -> [LiabilityRecord] {
        let sql = """
        SELECT id, name, liability_group, category, currency, balance, interest_rate
        FROM liabilities
        ORDER BY name COLLATE NOCASE DESC;
        """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(databaseMessage)
        }

        var records: [LiabilityRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            records.append(LiabilityRecord(
                id: sqlite3_column_int64(statement, 0),
                name: String(cString: sqlite3_column_text(statement, 1)),
                liabilityGroup: String(cString: sqlite3_column_text(statement, 2)),
                category: String(cString: sqlite3_column_text(statement, 3)),
                currency: String(cString: sqlite3_column_text(statement, 4)),
                balance: sqlite3_column_double(statement, 5),
                interestRate: sqlite3_column_type(statement, 6) == SQLITE_NULL
                    ? nil
                    : sqlite3_column_double(statement, 6)
            ))
        }
        return records
    }

    /// Deactivates an asset while preserving its historical database row.
    func deactivateAsset(id: Int64) throws {
        try execute("UPDATE assets SET is_active = 0, updated_at = CURRENT_TIMESTAMP WHERE id = \(id);")
    }

    /// Deactivates a liability while preserving its historical database row.
    func deactivateLiability(id: Int64) throws {
        try execute("UPDATE liabilities SET is_active = 0, updated_at = CURRENT_TIMESTAMP WHERE id = \(id);")
    }

    /// Updates an existing asset while preserving its database history.
    func updateAsset(
        id: Int64,
        name: String,
        assetGroup: String,
        category: String,
        currency: String,
        value: Double,
        ntdValue: Double
    ) throws {
        let sql = """
        UPDATE assets
        SET name = ?, asset_group = ?, category = ?, currency = ?, value = ?,
            ntd_value = ?, updated_at = CURRENT_TIMESTAMP
        WHERE id = ? AND is_active = 1;
        """
        try executePrepared(sql) { statement in
            let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(statement, 1, name, -1, transientDestructor)
            sqlite3_bind_text(statement, 2, assetGroup, -1, transientDestructor)
            sqlite3_bind_text(statement, 3, category, -1, transientDestructor)
            sqlite3_bind_text(statement, 4, currency, -1, transientDestructor)
            sqlite3_bind_double(statement, 5, value)
            sqlite3_bind_double(statement, 6, ntdValue)
            sqlite3_bind_int64(statement, 7, id)
        }
    }

    /// Updates an existing liability while preserving its database history.
    func updateLiability(
        id: Int64,
        name: String,
        liabilityGroup: String,
        category: String,
        currency: String,
        balance: Double,
        interestRate: Double?
    ) throws {
        let sql = """
        UPDATE liabilities
        SET name = ?, liability_group = ?, category = ?, currency = ?, balance = ?,
            interest_rate = ?, updated_at = CURRENT_TIMESTAMP
        WHERE id = ?;
        """
        try executePrepared(sql) { statement in
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
            sqlite3_bind_int64(statement, 7, id)
        }
    }

    /// Stores one daily financial snapshot for historical comparisons.
    func saveSnapshot(date: String, assets: AssetTotals, liabilities: LiabilityTotals) throws {
        let sql = """
        INSERT INTO snapshots
            (snapshot_date, total_assets_ntd, total_liabilities_ntd, net_worth_ntd,
             portfolio_value_ntd)
        VALUES (?, ?, ?, ?, 0)
        ON CONFLICT(snapshot_date) DO UPDATE SET
            total_assets_ntd = excluded.total_assets_ntd,
            total_liabilities_ntd = excluded.total_liabilities_ntd,
            net_worth_ntd = excluded.net_worth_ntd;
        """
        try executePrepared(sql) { statement in
            let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(statement, 1, date, -1, transientDestructor)
            sqlite3_bind_double(statement, 2, assets.total)
            sqlite3_bind_double(statement, 3, liabilities.total)
            sqlite3_bind_double(statement, 4, assets.total - liabilities.total)
        }
    }

    /// Returns the most recent snapshot before the supplied date.
    func previousSnapshot(before date: String) throws -> Snapshot? {
        let sql = """
        SELECT snapshot_date, total_assets_ntd, total_liabilities_ntd, net_worth_ntd
        FROM snapshots
        WHERE snapshot_date < ?
        ORDER BY snapshot_date DESC
        LIMIT 1;
        """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(databaseMessage)
        }
        let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, date, -1, transientDestructor)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return Snapshot(
            date: String(cString: sqlite3_column_text(statement, 0)),
            totalAssets: sqlite3_column_double(statement, 1),
            totalLiabilities: sqlite3_column_double(statement, 2),
            netWorth: sqlite3_column_double(statement, 3)
        )
    }

    private var databaseMessage: String {
        guard let database else { return "Unknown SQLite error" }
        return String(cString: sqlite3_errmsg(database))
    }

    private func executePrepared(
        _ sql: String,
        bind: (OpaquePointer?) -> Void
    ) throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(databaseMessage)
        }
        bind(statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.queryFailed(databaseMessage)
        }
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

    CREATE TABLE IF NOT EXISTS holdings (
        id INTEGER PRIMARY KEY,
        asset_id INTEGER NOT NULL UNIQUE,
        symbol TEXT NOT NULL,
        security_name TEXT NOT NULL,
        market TEXT NOT NULL CHECK (market IN ('TW', 'US')),
        instrument_type TEXT NOT NULL DEFAULT 'stock' CHECK (
            instrument_type IN ('stock', 'etf')
        ),
        etf_type TEXT CHECK (
            etf_type IS NULL OR etf_type IN ('equity', 'bond')
        ),
        currency TEXT NOT NULL,
        shares NUMERIC NOT NULL DEFAULT 0,
        total_cost NUMERIC NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS snapshots (
        id INTEGER PRIMARY KEY,
        snapshot_date TEXT NOT NULL UNIQUE,
        total_assets_ntd NUMERIC NOT NULL,
        total_liabilities_ntd NUMERIC NOT NULL,
        net_worth_ntd NUMERIC NOT NULL,
        portfolio_value_ntd NUMERIC NOT NULL DEFAULT 0,
        asset_allocation_json TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    );
    """

    private func addNTDValueColumnIfNeeded() throws {
        do {
            try execute("ALTER TABLE assets ADD COLUMN ntd_value NUMERIC NOT NULL DEFAULT 0;")
        } catch DatabaseError.queryFailed(let message) where message.contains("duplicate column name") {
            // The column already exists in databases created by newer versions.
        }
    }

    private func addHoldingsClassificationColumnsIfNeeded() throws {
        do {
            try execute("ALTER TABLE holdings ADD COLUMN instrument_type TEXT NOT NULL DEFAULT 'stock';")
        } catch DatabaseError.queryFailed(let message) where message.contains("duplicate column name") {
            // The column already exists.
        }

        do {
            try execute("ALTER TABLE holdings ADD COLUMN etf_type TEXT;")
        } catch DatabaseError.queryFailed(let message) where message.contains("duplicate column name") {
            // The column already exists.
        }
    }
}
