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

    struct PortfolioTotals {
        let investedNTD: Double
        let marketValueNTD: Double
        let totalPLNTD: Double
        let pricedHoldings: Int
    }

    struct AllocationRecord: Identifiable {
        let id: Int64
        let name: String
        let valueNTD: Double
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

    struct HoldingRecord: Identifiable {
        let id: Int64
        let assetID: Int64
        let symbol: String
        let securityName: String
        let market: String
        let instrumentType: String
        let etfType: String?
        let currency: String
        let shares: Double
        let totalCost: Double
        let assetGroup: String
        let category: String
        let marketPrice: Double?
        let marketValue: Double?
        let capitalGainLoss: Double?
    }

    struct SymbolSuggestion: Identifiable {
        let id: String
        let symbol: String
        let securityName: String
        let market: String
    }

    struct RecurringSchedule: Identifiable {
        let id: Int64
        let plannedAmount: Double
        let currency: String
        let frequency: String
        let executionDay: Int
        let startDate: String
    }

    struct RecurringRecord: Identifiable {
        let id: Int64
        let holdingID: Int64
        let symbol: String
        let securityName: String
        let schedules: [RecurringSchedule]

        var currency: String { schedules.first?.currency ?? "NTD" }
        var frequency: String { schedules.first?.frequency ?? "monthly" }
        var executionDay: Int { schedules.first?.executionDay ?? 1 }
        var plannedAmount: Double { schedules.reduce(0) { $0 + $1.plannedAmount } }
    }

    struct RecurringPurchaseRecord: Identifiable {
        let id: Int64
        let tradeDate: String
        let shares: Double
        let amount: Double
        let currency: String
    }

    struct DividendRecord: Identifiable {
        let id: Int64
        let holdingID: Int64
        let symbol: String
        let securityName: String
        let payDate: String
        let amount: Double
        let currency: String
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

    /// Marks a holding as an active recurring-investment item.
    func createRecurringInvestment(
        holdingID: Int64,
        currency: String,
        startDate: String,
        plannedAmount: Double = 0,
        frequency: String = "monthly",
        executionDay: Int = 1
    ) throws {
        let sql = """
        INSERT INTO recurring_investments
            (holding_id, planned_amount, currency, frequency, execution_day, start_date)
        VALUES (?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(databaseMessage)
        }

        let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_int64(statement, 1, holdingID)
        sqlite3_bind_double(statement, 2, plannedAmount)
        sqlite3_bind_text(statement, 3, currency, -1, transientDestructor)
        sqlite3_bind_text(statement, 4, frequency, -1, transientDestructor)
        sqlite3_bind_int(statement, 5, Int32(executionDay))
        sqlite3_bind_text(statement, 6, startDate, -1, transientDestructor)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.queryFailed(databaseMessage)
        }
    }

    /// Creates a holding linked to an existing asset record.
    func createHolding(
        assetID: Int64,
        symbol: String,
        securityName: String,
        market: String,
        instrumentType: String,
        etfType: String?,
        currency: String,
        shares: Double,
        totalCost: Double
    ) throws -> Int64 {
        let sql = """
        INSERT INTO holdings
            (asset_id, symbol, security_name, market, instrument_type, etf_type,
             currency, shares, total_cost)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(databaseMessage)
        }

        let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_int64(statement, 1, assetID)
        sqlite3_bind_text(statement, 2, symbol, -1, transientDestructor)
        sqlite3_bind_text(statement, 3, securityName, -1, transientDestructor)
        sqlite3_bind_text(statement, 4, market, -1, transientDestructor)
        sqlite3_bind_text(statement, 5, instrumentType, -1, transientDestructor)
        if let etfType {
            sqlite3_bind_text(statement, 6, etfType, -1, transientDestructor)
        } else {
            sqlite3_bind_null(statement, 6)
        }
        sqlite3_bind_text(statement, 7, currency, -1, transientDestructor)
        sqlite3_bind_double(statement, 8, shares)
        sqlite3_bind_double(statement, 9, totalCost)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.queryFailed(databaseMessage)
        }
        return sqlite3_last_insert_rowid(database)
    }

    /// Updates the identifier and original-currency values of a holding.
    func updateHolding(
        id: Int64,
        symbol: String,
        securityName: String,
        market: String,
        instrumentType: String,
        etfType: String?,
        currency: String,
        shares: Double,
        totalCost: Double
    ) throws {
        let sql = """
        UPDATE holdings
        SET symbol = ?, security_name = ?, market = ?, instrument_type = ?, etf_type = ?, currency = ?,
            shares = ?, total_cost = ?, updated_at = CURRENT_TIMESTAMP
        WHERE id = ?;
        """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(databaseMessage)
        }
        let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, symbol, -1, transientDestructor)
        sqlite3_bind_text(statement, 2, securityName, -1, transientDestructor)
        sqlite3_bind_text(statement, 3, market, -1, transientDestructor)
        sqlite3_bind_text(statement, 4, instrumentType, -1, transientDestructor)
        if let etfType {
            sqlite3_bind_text(statement, 5, etfType, -1, transientDestructor)
        } else {
            sqlite3_bind_null(statement, 5)
        }
        sqlite3_bind_text(statement, 6, currency, -1, transientDestructor)
        sqlite3_bind_double(statement, 7, shares)
        sqlite3_bind_double(statement, 8, totalCost)
        sqlite3_bind_int64(statement, 9, id)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.queryFailed(databaseMessage)
        }
    }

    /// Deletes a holding and its private backing asset.
    func deleteHolding(id: Int64) throws {
        try execute("""
        DELETE FROM assets
        WHERE id = (SELECT asset_id FROM holdings WHERE id = \(id));
        """)
    }

    /// Returns holdings stored in the local database for Portfolio display.
    func listHoldings() throws -> [HoldingRecord] {
        let sql = """
        SELECT h.id, h.asset_id, h.symbol, h.security_name, h.market, h.instrument_type, h.etf_type,
               h.currency, h.shares, h.total_cost,
               (SELECT price FROM market_prices mp
                WHERE mp.symbol = h.symbol AND mp.market = h.market
                ORDER BY mp.observed_at DESC, mp.id DESC LIMIT 1) AS market_price,
               a.asset_group, a.category,
               (SELECT COALESCE(SUM(d.amount), 0) FROM dividends d WHERE d.holding_id = h.id) AS dividends
        FROM holdings AS h
        JOIN assets AS a ON a.id = h.asset_id
        ORDER BY substr(security_name, 1, 1) COLLATE NOCASE ASC,
                 security_name COLLATE NOCASE ASC;
        """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(databaseMessage)
        }

        var records: [HoldingRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            records.append(HoldingRecord(
                id: sqlite3_column_int64(statement, 0),
                assetID: sqlite3_column_int64(statement, 1),
                symbol: String(cString: sqlite3_column_text(statement, 2)),
                securityName: String(cString: sqlite3_column_text(statement, 3)),
                market: String(cString: sqlite3_column_text(statement, 4)),
                instrumentType: String(cString: sqlite3_column_text(statement, 5)),
                etfType: sqlite3_column_type(statement, 6) == SQLITE_NULL
                    ? nil
                    : String(cString: sqlite3_column_text(statement, 6)),
                currency: String(cString: sqlite3_column_text(statement, 7)),
                shares: sqlite3_column_double(statement, 8),
                totalCost: sqlite3_column_double(statement, 9),
                assetGroup: String(cString: sqlite3_column_text(statement, 11)),
                category: String(cString: sqlite3_column_text(statement, 12)),
                marketPrice: sqlite3_column_type(statement, 10) == SQLITE_NULL
                    ? nil : sqlite3_column_double(statement, 10),
                marketValue: sqlite3_column_type(statement, 10) == SQLITE_NULL
                    ? nil : sqlite3_column_double(statement, 10) * sqlite3_column_double(statement, 8),
                capitalGainLoss: sqlite3_column_type(statement, 10) == SQLITE_NULL
                    ? nil : sqlite3_column_double(statement, 10) * sqlite3_column_double(statement, 8) - sqlite3_column_double(statement, 9) + sqlite3_column_double(statement, 13)
            ))
        }
        return records
    }

    /// Returns cached symbol suggestions for the holding-entry form.
    func symbolSuggestions(prefix: String, market: String) throws -> [SymbolSuggestion] {
        let sql = """
        SELECT symbol, security_name, market FROM holdings
        WHERE market = ? AND (symbol LIKE ? OR security_name LIKE ?)
        GROUP BY symbol, security_name, market
        ORDER BY security_name COLLATE NOCASE
        LIMIT 8;
        """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(databaseMessage)
        }
        let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let pattern = "%\(prefix)%"
        sqlite3_bind_text(statement, 1, market, -1, transientDestructor)
        sqlite3_bind_text(statement, 2, pattern, -1, transientDestructor)
        sqlite3_bind_text(statement, 3, pattern, -1, transientDestructor)

        var suggestions: [SymbolSuggestion] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let symbol = String(cString: sqlite3_column_text(statement, 0))
            let name = String(cString: sqlite3_column_text(statement, 1))
            suggestions.append(SymbolSuggestion(id: "\(market)-\(symbol)", symbol: symbol, securityName: name, market: market))
        }
        return suggestions
    }

    /// Returns the latest stored market price for a symbol.
    func latestMarketPrice(symbol: String, market: String) throws -> Double? {
        try latestNumber(
            sql: "SELECT price FROM market_prices WHERE symbol = ? AND market = ? ORDER BY observed_at DESC, id DESC LIMIT 1;",
            bindings: [symbol, market]
        )
    }

    /// Returns the latest stored exchange rate for a currency pair.
    func latestExchangeRate(base: String, quote: String) throws -> Double? {
        try latestNumber(
            sql: "SELECT rate FROM exchange_rates WHERE base_currency = ? AND quote_currency = ? ORDER BY observed_at DESC, id DESC LIMIT 1;",
            bindings: [base, quote]
        )
    }

    /// Stores one market price observation.
    func insertMarketPrice(symbol: String, market: String, price: Double, currency: String, observedAt: String, source: String) throws {
        try insertObservation(
            sql: "INSERT INTO market_prices (symbol, market, price, currency, observed_at, source) VALUES (?, ?, ?, ?, ?, ?);",
            values: [symbol, market, String(price), currency, observedAt, source]
        )
    }

    /// Stores one exchange-rate observation.
    func insertExchangeRate(base: String, quote: String, rate: Double, observedAt: String, source: String) throws {
        try insertObservation(
            sql: "INSERT INTO exchange_rates (base_currency, quote_currency, rate, observed_at, source) VALUES (?, ?, ?, ?, ?);",
            values: [base, quote, String(rate), observedAt, source]
        )
    }

    private func insertObservation(sql: String, values: [String]) throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(databaseMessage)
        }
        let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, transientDestructor)
        }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.queryFailed(databaseMessage)
        }
    }

    private func latestNumber(sql: String, bindings: [String]) throws -> Double? {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(databaseMessage)
        }
        let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, binding) in bindings.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), binding, -1, transientDestructor)
        }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return sqlite3_column_double(statement, 0)
    }

    /// Returns active recurring investment plans and their holding names.
    func listRecurringInvestments() throws -> [RecurringRecord] {
        let sql = """
        SELECT ri.id, ri.holding_id, h.symbol, h.security_name,
               ri.planned_amount, ri.currency, ri.frequency, ri.execution_day, ri.start_date
        FROM recurring_investments ri
        JOIN holdings h ON h.id = ri.holding_id
        WHERE ri.is_active = 1
        ORDER BY h.security_name COLLATE NOCASE DESC;
        """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(databaseMessage)
        }

        var grouped: [Int64: (symbol: String, securityName: String, schedules: [RecurringSchedule])] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let holdingID = sqlite3_column_int64(statement, 1)
            let schedule = RecurringSchedule(
                id: sqlite3_column_int64(statement, 0),
                plannedAmount: sqlite3_column_double(statement, 4),
                currency: String(cString: sqlite3_column_text(statement, 5)),
                frequency: String(cString: sqlite3_column_text(statement, 6)),
                executionDay: Int(sqlite3_column_int(statement, 7)),
                startDate: String(cString: sqlite3_column_text(statement, 8))
            )
            if var existing = grouped[holdingID] {
                existing.schedules.append(schedule)
                grouped[holdingID] = existing
            } else {
                grouped[holdingID] = (
                    String(cString: sqlite3_column_text(statement, 2)),
                    String(cString: sqlite3_column_text(statement, 3)),
                    [schedule]
                )
            }
        }
        return grouped.map { holdingID, value in
            RecurringRecord(
                id: holdingID,
                holdingID: holdingID,
                symbol: value.symbol,
                securityName: value.securityName,
                schedules: value.schedules
            )
        }.sorted { $0.securityName.localizedCaseInsensitiveCompare($1.securityName) == .orderedAscending }
    }

    func deleteRecurringInvestment(id: Int64) throws {
        try execute("DELETE FROM recurring_investments WHERE id = \(id);")
    }

    func updateRecurringInvestment(id: Int64, plannedAmount: Double, currency: String, frequency: String, executionDay: Int) throws {
        let sql = """
        UPDATE recurring_investments
        SET planned_amount = ?, currency = ?, frequency = ?, execution_day = ?
        WHERE id = ?;
        """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw DatabaseError.queryFailed(databaseMessage) }
        let destructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_double(statement, 1, plannedAmount)
        sqlite3_bind_text(statement, 2, currency, -1, destructor)
        sqlite3_bind_text(statement, 3, frequency, -1, destructor)
        sqlite3_bind_int(statement, 4, Int32(executionDay))
        sqlite3_bind_int64(statement, 5, id)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw DatabaseError.queryFailed(databaseMessage) }
    }

    func addRecurringPurchase(holdingID: Int64, tradeDate: String, shares: Double, amount: Double, currency: String) throws {
        try insertObservation(
            sql: "INSERT INTO recurring_purchases (holding_id, trade_date, shares, amount, currency) VALUES (?, ?, ?, ?, ?);",
            values: [String(holdingID), tradeDate, String(shares), String(amount), currency]
        )
        try execute("""
        UPDATE holdings
        SET shares = shares + \(shares),
            total_cost = total_cost + \(amount),
            updated_at = CURRENT_TIMESTAMP
        WHERE id = \(holdingID);
        """)
    }

    func listRecurringPurchases(holdingID: Int64) throws -> [RecurringPurchaseRecord] {
        let sql = """
        SELECT id, trade_date, shares, amount, currency
        FROM recurring_purchases
        WHERE holding_id = ?
        ORDER BY trade_date DESC, id DESC;
        """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw DatabaseError.queryFailed(databaseMessage) }
        sqlite3_bind_int64(statement, 1, holdingID)
        var records: [RecurringPurchaseRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            records.append(RecurringPurchaseRecord(
                id: sqlite3_column_int64(statement, 0),
                tradeDate: String(cString: sqlite3_column_text(statement, 1)),
                shares: sqlite3_column_double(statement, 2),
                amount: sqlite3_column_double(statement, 3),
                currency: String(cString: sqlite3_column_text(statement, 4))
            ))
        }
        return records
    }

    func addDividend(holdingID: Int64, payDate: String, amount: Double, currency: String) throws {
        try insertObservation(
            sql: "INSERT INTO dividends (holding_id, pay_date, amount, currency) VALUES (?, ?, ?, ?);",
            values: [String(holdingID), payDate, String(amount), currency]
        )
    }

    func listDividends() throws -> [DividendRecord] {
        let sql = """
        SELECT d.id, d.holding_id, h.symbol, h.security_name, d.pay_date, d.amount, d.currency
        FROM dividends d
        JOIN holdings h ON h.id = d.holding_id
        ORDER BY d.pay_date DESC, d.id DESC;
        """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw DatabaseError.queryFailed(databaseMessage) }
        var records: [DividendRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            records.append(DividendRecord(
                id: sqlite3_column_int64(statement, 0),
                holdingID: sqlite3_column_int64(statement, 1),
                symbol: String(cString: sqlite3_column_text(statement, 2)),
                securityName: String(cString: sqlite3_column_text(statement, 3)),
                payDate: String(cString: sqlite3_column_text(statement, 4)),
                amount: sqlite3_column_double(statement, 5),
                currency: String(cString: sqlite3_column_text(statement, 6))
            ))
        }
        return records
    }

    func updateDividend(id: Int64, payDate: String, amount: Double, currency: String) throws {
        let sql = "UPDATE dividends SET pay_date = ?, amount = ?, currency = ? WHERE id = ?;"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw DatabaseError.queryFailed(databaseMessage) }
        let destructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, payDate, -1, destructor)
        sqlite3_bind_double(statement, 2, amount)
        sqlite3_bind_text(statement, 3, currency, -1, destructor)
        sqlite3_bind_int64(statement, 4, id)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw DatabaseError.queryFailed(databaseMessage) }
    }

    func deleteDividend(id: Int64) throws {
        try execute("DELETE FROM dividends WHERE id = \(id);")
    }

    /// Returns asset totals in NTD, grouped by the balance-sheet asset group.
    func assetTotals() throws -> AssetTotals {
        let sql = """
        SELECT a.asset_group,
               COALESCE(SUM(
                   CASE
                       WHEN h.id IS NULL THEN CASE
                           WHEN a.currency = 'NTD' THEN a.ntd_value
                           ELSE COALESCE(
                               a.value * (
                                   SELECT er.rate FROM exchange_rates er
                                   WHERE er.base_currency = a.currency AND er.quote_currency = 'NTD'
                                   ORDER BY er.observed_at DESC, er.id DESC LIMIT 1
                               ), a.ntd_value
                           )
                       END
                       WHEN h.currency = 'NTD' THEN COALESCE(
                           h.shares * (
                               SELECT mp.price FROM market_prices mp
                               WHERE mp.symbol = h.symbol AND mp.market = h.market
                               ORDER BY mp.observed_at DESC, mp.id DESC LIMIT 1
                           ), a.ntd_value
                       )
                       ELSE COALESCE(
                           h.shares * (
                               SELECT mp.price FROM market_prices mp
                               WHERE mp.symbol = h.symbol AND mp.market = h.market
                               ORDER BY mp.observed_at DESC, mp.id DESC LIMIT 1
                           ) * (
                               SELECT er.rate FROM exchange_rates er
                               WHERE er.base_currency = h.currency AND er.quote_currency = 'NTD'
                               ORDER BY er.observed_at DESC, er.id DESC LIMIT 1
                           ), 0
                       )
                   END
               ), 0)
        FROM assets a
        LEFT JOIN holdings h ON h.asset_id = a.id
        WHERE a.is_active = 1
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

    /// Returns NTD totals for each user-defined asset subcategory.
    func assetCategoryTotals() throws -> [String: Double] {
        let sql = """
        SELECT a.asset_group,
               CASE WHEN h.id IS NULL THEN a.name ELSE a.category END AS child_name,
               COALESCE(SUM(
                   CASE
                       WHEN h.id IS NULL THEN CASE
                           WHEN a.currency = 'NTD' THEN a.ntd_value
                           ELSE COALESCE(
                               a.value * (
                                   SELECT er.rate FROM exchange_rates er
                                   WHERE er.base_currency = a.currency AND er.quote_currency = 'NTD'
                                   ORDER BY er.observed_at DESC, er.id DESC LIMIT 1
                               ), a.ntd_value
                           )
                       END
                       WHEN h.currency = 'NTD' THEN COALESCE(
                           h.shares * (SELECT mp.price FROM market_prices mp
                               WHERE mp.symbol = h.symbol AND mp.market = h.market
                               ORDER BY mp.observed_at DESC, mp.id DESC LIMIT 1), a.ntd_value)
                       ELSE COALESCE(
                           h.shares * (SELECT mp.price FROM market_prices mp
                               WHERE mp.symbol = h.symbol AND mp.market = h.market
                               ORDER BY mp.observed_at DESC, mp.id DESC LIMIT 1) *
                           (SELECT er.rate FROM exchange_rates er
                               WHERE er.base_currency = h.currency AND er.quote_currency = 'NTD'
                               ORDER BY er.observed_at DESC, er.id DESC LIMIT 1), 0)
                   END
               ), 0)
        FROM assets a
        LEFT JOIN holdings h ON h.asset_id = a.id
        WHERE a.is_active = 1
        GROUP BY a.asset_group, child_name;
        """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(databaseMessage)
        }

        var totals: [String: Double] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let group = String(cString: sqlite3_column_text(statement, 0))
            let child = String(cString: sqlite3_column_text(statement, 1))
            totals["\(group)|\(child)"] = sqlite3_column_double(statement, 2)
        }
        return totals
    }

    /// Returns portfolio totals converted to NTD using stored prices and rates.
    func portfolioTotals() throws -> PortfolioTotals {
        let sql = """
        SELECT
            COALESCE(SUM(h.total_cost * CASE WHEN h.currency = 'NTD' THEN 1 ELSE COALESCE((
                SELECT er.rate FROM exchange_rates er
                WHERE er.base_currency = h.currency AND er.quote_currency = 'NTD'
                ORDER BY er.observed_at DESC, er.id DESC LIMIT 1), 0) END), 0),
            COALESCE(SUM(CASE WHEN mp.price IS NOT NULL THEN
                mp.price * h.shares * CASE WHEN h.currency = 'NTD' THEN 1 ELSE COALESCE((
                    SELECT er.rate FROM exchange_rates er
                    WHERE er.base_currency = h.currency AND er.quote_currency = 'NTD'
                    ORDER BY er.observed_at DESC, er.id DESC LIMIT 1), 0) END
                ELSE 0 END), 0),
            COALESCE(SUM(CASE WHEN mp.price IS NOT NULL THEN
                (mp.price * h.shares - h.total_cost) * CASE WHEN h.currency = 'NTD' THEN 1 ELSE COALESCE((
                    SELECT er.rate FROM exchange_rates er
                    WHERE er.base_currency = h.currency AND er.quote_currency = 'NTD'
                    ORDER BY er.observed_at DESC, er.id DESC LIMIT 1), 0) END
                ELSE 0 END), 0)
            + COALESCE(SUM(
                (SELECT COALESCE(SUM(d.amount), 0) FROM dividends d WHERE d.holding_id = h.id)
                * CASE WHEN h.currency = 'NTD' THEN 1 ELSE COALESCE((
                    SELECT er.rate FROM exchange_rates er
                    WHERE er.base_currency = h.currency AND er.quote_currency = 'NTD'
                    ORDER BY er.observed_at DESC, er.id DESC LIMIT 1), 0) END
            ), 0),
            COUNT(mp.price)
        FROM holdings h
        LEFT JOIN market_prices mp ON mp.id = (
            SELECT mp2.id FROM market_prices mp2
            WHERE mp2.symbol = h.symbol AND mp2.market = h.market
            ORDER BY mp2.observed_at DESC, mp2.id DESC LIMIT 1
        );
        """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(databaseMessage)
        }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return PortfolioTotals(investedNTD: 0, marketValueNTD: 0, totalPLNTD: 0, pricedHoldings: 0)
        }
        return PortfolioTotals(
            investedNTD: sqlite3_column_double(statement, 0),
            marketValueNTD: sqlite3_column_double(statement, 1),
            totalPLNTD: sqlite3_column_double(statement, 2),
            pricedHoldings: Int(sqlite3_column_int(statement, 3))
        )
    }

    /// Returns the five largest priced holdings by current NTD value.
    func allocationRecords() throws -> [AllocationRecord] {
        let sql = """
        SELECT h.id, h.security_name,
               h.shares * mp.price * CASE WHEN h.currency = 'NTD' THEN 1 ELSE COALESCE((
                   SELECT er.rate FROM exchange_rates er
                   WHERE er.base_currency = h.currency AND er.quote_currency = 'NTD'
                   ORDER BY er.observed_at DESC, er.id DESC LIMIT 1), 0) END AS value_ntd
        FROM holdings h
        JOIN market_prices mp ON mp.id = (
            SELECT mp2.id FROM market_prices mp2
            WHERE mp2.symbol = h.symbol AND mp2.market = h.market
            ORDER BY mp2.observed_at DESC, mp2.id DESC LIMIT 1
        )
        ORDER BY value_ntd DESC
        LIMIT 5;
        """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(databaseMessage)
        }
        var records: [AllocationRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            records.append(AllocationRecord(
                id: sqlite3_column_int64(statement, 0),
                name: String(cString: sqlite3_column_text(statement, 1)),
                valueNTD: sqlite3_column_double(statement, 2)
            ))
        }
        return records
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
        SELECT a.id, a.name, a.asset_group, a.category, a.currency, a.value, a.ntd_value
        FROM assets a
        WHERE a.is_active = 1
          AND NOT EXISTS (
              SELECT 1
              FROM holdings h
              WHERE h.asset_id = a.id
          )
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

    CREATE TABLE IF NOT EXISTS recurring_investments (
        id INTEGER PRIMARY KEY,
        holding_id INTEGER NOT NULL,
        planned_amount NUMERIC NOT NULL,
        currency TEXT NOT NULL,
        frequency TEXT NOT NULL,
        execution_day INTEGER NOT NULL,
        start_date TEXT NOT NULL,
        end_date TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        notes TEXT,
        FOREIGN KEY (holding_id) REFERENCES holdings(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS recurring_purchases (
        id INTEGER PRIMARY KEY,
        holding_id INTEGER NOT NULL,
        trade_date TEXT NOT NULL,
        shares NUMERIC NOT NULL,
        amount NUMERIC NOT NULL,
        currency TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (holding_id) REFERENCES holdings(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS dividends (
        id INTEGER PRIMARY KEY,
        holding_id INTEGER NOT NULL,
        pay_date TEXT NOT NULL,
        amount NUMERIC NOT NULL,
        currency TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (holding_id) REFERENCES holdings(id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS market_prices (
        id INTEGER PRIMARY KEY,
        symbol TEXT NOT NULL,
        market TEXT NOT NULL,
        price NUMERIC NOT NULL,
        currency TEXT NOT NULL,
        observed_at TEXT NOT NULL,
        retrieved_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        source TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS exchange_rates (
        id INTEGER PRIMARY KEY,
        base_currency TEXT NOT NULL,
        quote_currency TEXT NOT NULL,
        rate NUMERIC NOT NULL,
        observed_at TEXT NOT NULL,
        retrieved_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        source TEXT NOT NULL
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
