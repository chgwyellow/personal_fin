import AppKit
import Charts
import Darwin
import Foundation
import SwiftUI

@main
struct PersonalFinanceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(appModel)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.automatic)
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var assetTotals = DatabaseManager.AssetTotals(
        liquidAsset: 0,
        liquidInvestment: 0,
        longTermInvestment: 0,
        otherAsset: 0
    )
    @Published private(set) var liabilityTotals = DatabaseManager.LiabilityTotals(
        shortTerm: 0,
        longTerm: 0
    )
    @Published private(set) var assets: [DatabaseManager.AssetRecord] = []
    @Published private(set) var assetCategoryTotals: [String: Double] = [:]
    @Published private(set) var portfolioTotals = DatabaseManager.PortfolioTotals(
        investedNTD: 0,
        marketValueNTD: 0,
        totalPLNTD: 0,
        pricedHoldings: 0
    )
    @Published private(set) var allocationRecords: [DatabaseManager.AllocationRecord] = []
    @Published private(set) var liabilities: [DatabaseManager.LiabilityRecord] = []
    @Published private(set) var holdingRecords: [DatabaseManager.HoldingRecord] = []
    @Published private(set) var recurringRecords: [DatabaseManager.RecurringRecord] = []
    @Published private(set) var dividendRecords: [DatabaseManager.DividendRecord] = []
    @Published private(set) var foreignCurrencyTransactions: [DatabaseManager.ForeignCurrencyTransactionRecord] = []
    @Published private(set) var incomeStatementItems: [DatabaseManager.IncomeStatementItem] = []
    @Published private(set) var statementAccounts: [String] = []
    @Published private(set) var foreignExchangeRates: [String: Double] = [:]
    @Published private(set) var foreignExchangeRatesUpdatedAt: Date?
    @Published private(set) var todayPLNTD: Double?
    @Published private(set) var isRefreshingMarketData = false
    @Published private(set) var snapshots: [DatabaseManager.Snapshot] = []
    @Published var snapshotError: String?
    private let databaseManager: DatabaseManager?
    private let marketDataClient = MarketDataClient()
    private var marketStreamTask: Task<Void, Never>?
    private var streamedSymbols: Set<String> = []

    init() {
        databaseManager = try? DatabaseManager()
        todayPLNTD = UserDefaults.standard.object(forKey: "portfolio.todayPnl") as? Double
        refreshAssets()
        refreshLiabilities()
        refreshHoldings()
        refreshRecurringInvestments()
        refreshDividends()
        refreshForeignCurrencyTransactions()
        refreshIncomeStatementItems()
        refreshStatementAccounts()
        refreshPortfolioTotals()
        refreshAllocations()
        refreshSnapshots()
    }

    func refreshAssets() {
        guard let databaseManager else { return }
        do {
            assetTotals = try databaseManager.assetTotals()
            assets = try databaseManager.listAssets()
            assetCategoryTotals = try databaseManager.assetCategoryTotals()
        } catch {
            NSLog("FinTrack asset query failed: %@", error.localizedDescription)
        }
    }

    func createAsset(
        name: String,
        assetGroup: String,
        category: String,
        currency: String,
        value: Double,
        ntdValue: Double
    ) throws {
        guard let databaseManager else {
            throw DatabaseManager.DatabaseError.openFailed("Database is unavailable")
        }
        _ = try databaseManager.createAsset(
            name: name,
            assetGroup: assetGroup,
            category: category,
            currency: currency,
            value: value,
            ntdValue: ntdValue
        )
        refreshAssets()
        refreshHoldings()
    }

    func refreshHoldings() {
        guard let databaseManager else { return }
        do {
            holdingRecords = try databaseManager.listHoldings()
        } catch {
            NSLog("FinTrack holdings query failed: %@", error.localizedDescription)
        }
    }

    func refreshRecurringInvestments() {
        guard let databaseManager else { return }
        do {
            recurringRecords = try databaseManager.listRecurringInvestments()
        } catch {
            NSLog("FinTrack recurring investment query failed: %@", error.localizedDescription)
        }
    }

    func createRecurringRule(
        holdingID: Int64,
        plannedAmount: Double,
        currency: String,
        frequency: String,
        executionDay: Int,
        startDate: String
    ) throws {
        guard let databaseManager else {
            throw DatabaseManager.DatabaseError.openFailed("Database is unavailable")
        }
        try databaseManager.createRecurringInvestment(
            holdingID: holdingID,
            currency: currency,
            startDate: startDate,
            plannedAmount: plannedAmount,
            frequency: frequency,
            executionDay: executionDay
        )
        refreshRecurringInvestments()
    }

    func deleteRecurringRule(rule: DatabaseManager.RecurringRecord) {
        guard let databaseManager else { return }
        do {
            for schedule in rule.schedules {
                try databaseManager.deleteRecurringInvestment(id: schedule.id)
            }
            refreshRecurringInvestments()
        } catch {
            NSLog("FinTrack recurring investment deletion failed: %@", error.localizedDescription)
        }
    }

    func addRecurringPurchase(holdingID: Int64, tradeDate: String, shares: Double, amount: Double, currency: String, fundingAssetID: Int64?) throws {
        guard let databaseManager else { throw DatabaseManager.DatabaseError.openFailed("Database is unavailable") }
        try databaseManager.addRecurringPurchase(holdingID: holdingID, tradeDate: tradeDate, shares: shares, amount: amount, currency: currency, fundingAssetID: fundingAssetID)
        refreshAssets()
        refreshHoldings()
        refreshPortfolioTotals()
        refreshAllocations()
        refreshRecurringInvestments()
        refreshForeignCurrencyTransactions()
    }

    func updateRecurringPurchase(id: Int64, tradeDate: String, shares: Double, amount: Double, fundingAssetID: Int64?) throws {
        guard let databaseManager else { throw DatabaseManager.DatabaseError.openFailed("Database is unavailable") }
        try databaseManager.updateRecurringPurchase(id: id, tradeDate: tradeDate, shares: shares, amount: amount, fundingAssetID: fundingAssetID)
        refreshAssets()
        refreshHoldings()
        refreshPortfolioTotals()
        refreshAllocations()
        refreshRecurringInvestments()
        refreshForeignCurrencyTransactions()
    }

    func deleteRecurringPurchase(id: Int64) throws {
        guard let databaseManager else { throw DatabaseManager.DatabaseError.openFailed("Database is unavailable") }
        try databaseManager.deleteRecurringPurchase(id: id)
        refreshAssets()
        refreshHoldings()
        refreshPortfolioTotals()
        refreshAllocations()
        refreshRecurringInvestments()
        refreshForeignCurrencyTransactions()
    }

    func updateRecurringRule(id: Int64, plannedAmount: Double, currency: String, frequency: String, executionDay: Int) throws {
        guard let databaseManager else { throw DatabaseManager.DatabaseError.openFailed("Database is unavailable") }
        try databaseManager.updateRecurringInvestment(
            id: id,
            plannedAmount: plannedAmount,
            currency: currency,
            frequency: frequency,
            executionDay: executionDay
        )
        refreshRecurringInvestments()
    }

    func recurringPurchases(holdingID: Int64) -> [DatabaseManager.RecurringPurchaseRecord] {
        guard let databaseManager else { return [] }
        return (try? databaseManager.listRecurringPurchases(holdingID: holdingID)) ?? []
    }

    func addDividend(holdingID: Int64, payDate: String, amount: Double, currency: String) throws {
        guard let databaseManager else { throw DatabaseManager.DatabaseError.openFailed("Database is unavailable") }
        try databaseManager.addDividend(holdingID: holdingID, payDate: payDate, amount: amount, currency: currency)
        refreshDividends()
        refreshHoldings()
        refreshPortfolioTotals()
    }

    func refreshDividends() {
        guard let databaseManager else { return }
        dividendRecords = (try? databaseManager.listDividends()) ?? []
    }

    func refreshForeignCurrencyTransactions() {
        guard let databaseManager else { return }
        foreignCurrencyTransactions = (try? databaseManager.listForeignCurrencyTransactions()) ?? []
    }

    func createForeignCurrencyTransaction(
        purpose: String,
        currency: String,
        foreignAmount: Double,
        ntdAmount: Double?,
        rate: Double?,
        tradeDate: String
    ) throws {
        guard let databaseManager else { throw DatabaseManager.DatabaseError.openFailed("Database is unavailable") }
        try databaseManager.createForeignCurrencyTransaction(
            purpose: purpose,
            currency: currency,
            foreignAmount: foreignAmount,
            ntdAmount: ntdAmount,
            rate: rate,
            tradeDate: tradeDate
        )
        refreshForeignCurrencyTransactions()
        refreshAssets()
    }

    func deleteForeignCurrencyTransaction(id: Int64) {
        guard let databaseManager else { return }
        do {
            try databaseManager.deleteForeignCurrencyTransaction(id: id)
            refreshForeignCurrencyTransactions()
            refreshAssets()
        } catch {
            NSLog("FinTrack foreign-currency transaction deletion failed: %@", error.localizedDescription)
        }
    }

    func refreshIncomeStatementItems() {
        guard let databaseManager else { return }
        incomeStatementItems = (try? databaseManager.listIncomeStatementItems()) ?? []
    }

    func refreshStatementAccounts() {
        guard let databaseManager else { return }
        statementAccounts = (try? databaseManager.listStatementAccounts()) ?? []
    }

    func createIncomeStatementItem(section: String, parentID: Int64?, name: String, amount: Double, accountName: String) throws {
        guard let databaseManager else { throw DatabaseManager.DatabaseError.openFailed("Database is unavailable") }
        if !accountName.isEmpty { try databaseManager.ensureStatementAccount(name: accountName) }
        try databaseManager.createIncomeStatementItem(section: section, parentID: parentID, name: name, amount: amount, accountName: accountName)
        refreshIncomeStatementItems()
        refreshStatementAccounts()
    }

    func updateIncomeStatementItem(id: Int64, name: String, amount: Double, accountName: String) throws {
        guard let databaseManager else { throw DatabaseManager.DatabaseError.openFailed("Database is unavailable") }
        if !accountName.isEmpty { try databaseManager.ensureStatementAccount(name: accountName) }
        try databaseManager.updateIncomeStatementItem(id: id, name: name, amount: amount, accountName: accountName)
        refreshIncomeStatementItems()
        refreshStatementAccounts()
    }

    func deleteIncomeStatementItem(id: Int64) {
        guard let databaseManager else { return }
        do {
            try databaseManager.deleteIncomeStatementItem(id: id)
            refreshIncomeStatementItems()
        } catch {
            NSLog("FinTrack income statement item deletion failed: %@", error.localizedDescription)
        }
    }

    func updateDividend(id: Int64, payDate: String, amount: Double, currency: String) throws {
        guard let databaseManager else { throw DatabaseManager.DatabaseError.openFailed("Database is unavailable") }
        try databaseManager.updateDividend(id: id, payDate: payDate, amount: amount, currency: currency)
        refreshDividends()
        refreshHoldings()
        refreshPortfolioTotals()
    }

    func deleteDividend(id: Int64) {
        guard let databaseManager else { return }
        do {
            try databaseManager.deleteDividend(id: id)
            refreshDividends()
            refreshHoldings()
            refreshPortfolioTotals()
        } catch {
            NSLog("FinTrack dividend deletion failed: %@", error.localizedDescription)
        }
    }

    func symbolSuggestions(prefix: String, market: String) -> [DatabaseManager.SymbolSuggestion] {
        guard let databaseManager, !prefix.isEmpty else { return [] }
        return (try? databaseManager.symbolSuggestions(prefix: prefix, market: market)) ?? []
    }

    func searchMarketSymbols(query: String) async -> [MarketDataClient.SearchResult] {
        do {
            return try await marketDataClient.searchSymbols(query: query)
        } catch {
            NSLog("FinTrack symbol search failed: %@", error.localizedDescription)
            return []
        }
    }

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
        guard let databaseManager else {
            throw DatabaseManager.DatabaseError.openFailed("Database is unavailable")
        }
        try databaseManager.updateHolding(
            id: id,
            symbol: symbol,
            securityName: securityName,
            market: market,
            instrumentType: instrumentType,
            etfType: etfType,
            currency: currency,
            shares: shares,
            totalCost: totalCost
        )
        refreshAssets()
        refreshHoldings()
    }

    func deleteHolding(id: Int64) {
        guard let databaseManager else { return }
        do {
            try databaseManager.deleteHolding(id: id)
            refreshAssets()
            refreshHoldings()
            refreshRecurringInvestments()
        } catch {
            NSLog("FinTrack holding deletion failed: %@", error.localizedDescription)
        }
    }

    func refreshMarketData() async {
        guard let databaseManager else { return }
        guard !isRefreshingMarketData else { return }
        isRefreshingMarketData = true
        defer { isRefreshingMarketData = false }
        let records = holdingRecords
        startMarketPriceStream()
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())
        var dailyQuotes: [(DatabaseManager.HoldingRecord, MarketDataClient.Quote)] = []

        for holding in records {
            do {
                if let quote = try await marketDataClient.fetchQuote(symbol: holding.symbol) {
                    try databaseManager.insertMarketPrice(
                        symbol: holding.symbol,
                        market: holding.market,
                        // Yahoo's regularMarketPrice is intentionally used here.
                        // PRE/POST market values are not part of FinTrack TODAY.
                        price: quote.price,
                        currency: quote.currency,
                        observedAt: timestamp,
                        source: "Yahoo Finance"
                    )
                    if let previousClose = quote.previousClose, previousClose > 0 {
                        try databaseManager.savePreviousClose(
                            symbol: holding.symbol,
                            market: holding.market,
                            price: previousClose,
                            currency: quote.currency,
                            observedAt: timestamp
                        )
                    }
                    dailyQuotes.append((holding, quote))
                }
            } catch {
                NSLog("FinTrack price refresh failed for %@: %@", holding.symbol, error.localizedDescription)
            }
        }

        for currency in Set((records.map(\.currency) + assets.map(\.currency))).filter({ $0 != "NTD" }) {
            do {
                if let rate = try await marketDataClient.fetchExchangeRate(baseCurrency: currency) {
                    try databaseManager.insertExchangeRate(
                        base: currency,
                        quote: "NTD",
                        rate: rate,
                        observedAt: timestamp,
                        source: "ExchangeRate-API"
                    )
                }
            } catch {
                NSLog("FinTrack exchange-rate refresh failed for %@: %@", currency, error.localizedDescription)
            }
        }

        updateTodayProfitLoss(records: records, quotes: dailyQuotes, databaseManager: databaseManager)

        refreshAssets()
        refreshHoldings()
        refreshPortfolioTotals()
        refreshAllocations()
        saveDailySnapshotIfDue()
    }

    private func updateTodayProfitLoss(
        records: [DatabaseManager.HoldingRecord],
        quotes: [(DatabaseManager.HoldingRecord, MarketDataClient.Quote)],
        databaseManager: DatabaseManager
    ) {
        let freshQuotes = Dictionary(uniqueKeysWithValues: quotes.map { ("\($0.0.market)|\($0.0.symbol)", $0.1) })
        var dailyPnL = 0.0
        var hasValidResult = false
        for holding in records {
            let key = "\(holding.market)|\(holding.symbol)"
            let quoteRecord = freshQuotes[key]
            let cachedCurrentPrice: Double? = try? databaseManager.latestMarketPrice(symbol: holding.symbol, market: holding.market)
            let cachedPreviousClose: Double? = try? databaseManager.latestPreviousClose(symbol: holding.symbol, market: holding.market)
            // A quote is normalized to the regular session price only.  After
            // the session closes this is the latest regular close; if the
            // network is unavailable, the last persisted regular price is the
            // safe fallback.  Never use PRE/POST market values for TODAY.
            let currentPrice: Double = quoteRecord?.price ?? cachedCurrentPrice ?? 0
            let previousClose: Double = quoteRecord?.previousClose ?? cachedPreviousClose ?? 0
            guard currentPrice > 0, previousClose > 0 else { continue }
            let rate = holding.currency == "NTD"
                ? 1
                : ((try? databaseManager.latestExchangeRate(base: holding.currency, quote: "NTD")) ?? 0)
            guard rate > 0 else { continue }
            dailyPnL += (currentPrice - previousClose) * holding.shares * rate
            hasValidResult = true
        }
        // A failed/empty refresh must not erase the last valid daily result.
        if hasValidResult {
            todayPLNTD = dailyPnL
            UserDefaults.standard.set(dailyPnL, forKey: "portfolio.todayPnl")
        }
    }

    /// One shared stream is used for all holdings.  It accepts regular-session
    /// ticks only; REST remains the initialization and recovery path.
    func startMarketPriceStream() {
        let symbols = Set(holdingRecords.map(\.symbol))
        if symbols.isEmpty {
            marketStreamTask?.cancel()
            marketStreamTask = nil
            streamedSymbols = []
            return
        }
        guard symbols != streamedSymbols else { return }
        marketStreamTask?.cancel()
        streamedSymbols = symbols
        let orderedSymbols = symbols.sorted()
        marketStreamTask = Task { @MainActor [weak self] in
            await self?.runMarketPriceStream(symbols: orderedSymbols)
        }
    }

    private func runMarketPriceStream(symbols: [String]) async {
        guard let url = URL(string: "wss://streamer.finance.yahoo.com/?version=2"),
              let subscription = YahooMarketStream.subscribeMessage(symbols: symbols) else { return }

        while !Task.isCancelled {
            let socket = URLSession.shared.webSocketTask(with: url)
            socket.resume()
            do {
                try await socket.send(.string(subscription))
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    guard case .data(let data) = message,
                          let tick = YahooMarketStream.decode(data),
                          tick.marketHours == 1 else { continue }
                    applyMarketStreamTick(tick)
                }
            } catch {
                socket.cancel(with: .goingAway, reason: nil)
                if !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                }
            }
        }
    }

    private func applyMarketStreamTick(_ tick: YahooMarketStream.Tick) {
        guard let databaseManager,
              let holding = holdingRecords.first(where: { $0.symbol == tick.symbol }) else { return }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        do {
            try databaseManager.insertMarketPrice(
                symbol: holding.symbol,
                market: holding.market,
                price: tick.price,
                currency: tick.currency ?? holding.currency,
                observedAt: timestamp,
                source: "Yahoo Finance WebSocket"
            )
            if let previousClose = tick.previousClose, previousClose > 0 {
                try databaseManager.savePreviousClose(
                    symbol: holding.symbol,
                    market: holding.market,
                    price: previousClose,
                    currency: tick.currency ?? holding.currency,
                    observedAt: timestamp
                )
            }
            updateTodayProfitLoss(records: holdingRecords, quotes: [], databaseManager: databaseManager)
            refreshHoldings()
            refreshPortfolioTotals()
            refreshAllocations()
        } catch {
            NSLog("FinTrack WebSocket price update failed for %@: %@", tick.symbol, error.localizedDescription)
        }
    }

    func saveDailySnapshotIfDue() {
        guard let databaseManager else { return }
        let scheduledTime = UserDefaults.standard.string(forKey: "snapshotTime") ?? "23:00"
        let parts = scheduledTime.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return }
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        guard let hour = now.hour, let minute = now.minute,
              hour > parts[0] || (hour == parts[0] && minute >= parts[1]) else { return }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let snapshotDate = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let dateString = formatter.string(from: snapshotDate)
        guard !snapshots.contains(where: { $0.date == dateString }) else { return }
        do {
            try databaseManager.saveSnapshot(
                date: dateString,
                assets: assetTotals,
                liabilities: liabilityTotals,
                detailValues: (try? databaseManager.snapshotDetailValues()) ?? [:]
            )
            refreshSnapshots()
        } catch {
            NSLog("FinTrack snapshot save failed: %@", error.localizedDescription)
        }
    }

    func refreshSnapshots() {
        guard let databaseManager else { return }
        snapshots = (try? databaseManager.listSnapshots()) ?? []
    }

    @discardableResult
    func saveManualSnapshot() -> Bool {
        guard let databaseManager else {
            snapshotError = "Snapshot storage is unavailable."
            return false
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        do {
            try databaseManager.saveSnapshot(
                date: formatter.string(from: Date()),
                assets: assetTotals,
                liabilities: liabilityTotals,
                detailValues: (try? databaseManager.snapshotDetailValues()) ?? [:]
            )
            refreshSnapshots()
            snapshotError = nil
            return true
        } catch {
            NSLog("FinTrack manual snapshot save failed: %@", error.localizedDescription)
            snapshotError = error.localizedDescription
            return false
        }
    }

    func refreshForeignExchangeRates() async {
        guard let databaseManager else { return }
        let currencies = Set(assets.map(\.currency)).filter { $0 != "NTD" }
        var refreshedRates: [String: Double] = [:]

        for currency in currencies {
            do {
                if let rate = try await marketDataClient.fetchExchangeRate(baseCurrency: currency) {
                    try databaseManager.insertExchangeRate(
                        base: currency,
                        quote: "NTD",
                        rate: rate,
                        observedAt: ISO8601DateFormatter().string(from: Date()),
                        source: "ExchangeRate-API"
                    )
                    refreshedRates[currency] = rate
                }
            } catch {
                NSLog("FinTrack foreign-currency refresh failed for %@: %@", currency, error.localizedDescription)
                if let cached = try? databaseManager.latestExchangeRate(base: currency, quote: "NTD") {
                    refreshedRates[currency] = cached
                }
            }
        }

        foreignExchangeRates = refreshedRates
        foreignExchangeRatesUpdatedAt = Date()
    }

    func refreshPortfolioTotals() {
        guard let databaseManager else { return }
        do {
            portfolioTotals = try databaseManager.portfolioTotals()
        } catch {
            NSLog("FinTrack portfolio totals query failed: %@", error.localizedDescription)
        }
    }

    func refreshAllocations() {
        guard let databaseManager else { return }
        do {
            allocationRecords = try databaseManager.allocationRecords()
        } catch {
            NSLog("FinTrack allocation query failed: %@", error.localizedDescription)
        }
    }

    func createHolding(
        assetName: String,
        assetGroup: String,
        category: String,
        symbol: String,
        securityName: String,
        market: String,
        instrumentType: String,
        etfType: String?,
        currency: String,
        shares: Double,
        totalCost: Double,
        isRecurringHolding: Bool
    ) throws {
        guard let databaseManager else {
            throw DatabaseManager.DatabaseError.openFailed("Database is unavailable")
        }
        let assetID = try databaseManager.createAsset(
            name: assetName,
            assetGroup: assetGroup,
            category: category,
            currency: currency,
            value: totalCost,
            ntdValue: currency == "NTD" ? totalCost : 0
        )
        let holdingID = try databaseManager.createHolding(
            assetID: assetID,
            symbol: symbol,
            securityName: securityName,
            market: market,
            instrumentType: instrumentType,
            etfType: etfType,
            currency: currency,
            shares: shares,
            totalCost: totalCost
        )
        if isRecurringHolding {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            try databaseManager.createRecurringInvestment(
                holdingID: holdingID,
                currency: currency,
                startDate: formatter.string(from: Date())
            )
        }
        refreshAssets()
        refreshHoldings()
        refreshRecurringInvestments()
        refreshPortfolioTotals()
        refreshAllocations()
    }

    func refreshLiabilities() {
        guard let databaseManager else { return }
        do {
            liabilityTotals = try databaseManager.liabilityTotals()
            liabilities = try databaseManager.listLiabilities()
        } catch {
            NSLog("FinTrack liability query failed: %@", error.localizedDescription)
        }
    }

    func createLiability(
        name: String,
        liabilityGroup: String,
        category: String,
        currency: String,
        balance: Double,
        interestRate: Double?
    ) throws {
        guard let databaseManager else {
            throw DatabaseManager.DatabaseError.openFailed("Database is unavailable")
        }
        _ = try databaseManager.createLiability(
            name: name,
            liabilityGroup: liabilityGroup,
            category: category,
            currency: currency,
            balance: balance,
            interestRate: interestRate
        )
        refreshLiabilities()
    }

    func deleteAsset(id: Int64) {
        guard let databaseManager else { return }
        do {
            try databaseManager.deactivateAsset(id: id)
            refreshAssets()
        } catch {
            NSLog("FinTrack asset deletion failed: %@", error.localizedDescription)
        }
    }

    func deleteLiability(id: Int64) {
        guard let databaseManager else { return }
        do {
            try databaseManager.deactivateLiability(id: id)
            refreshLiabilities()
        } catch {
            NSLog("FinTrack liability deletion failed: %@", error.localizedDescription)
        }
    }

    func updateAsset(
        id: Int64,
        name: String,
        assetGroup: String,
        category: String,
        currency: String,
        value: Double,
        ntdValue: Double
    ) throws {
        guard let databaseManager else {
            throw DatabaseManager.DatabaseError.openFailed("Database is unavailable")
        }
        try databaseManager.updateAsset(
            id: id,
            name: name,
            assetGroup: assetGroup,
            category: category,
            currency: currency,
            value: value,
            ntdValue: ntdValue
        )
        refreshAssets()
    }

    func updateLiability(
        id: Int64,
        name: String,
        liabilityGroup: String,
        category: String,
        currency: String,
        balance: Double,
        interestRate: Double?
    ) throws {
        guard let databaseManager else {
            throw DatabaseManager.DatabaseError.openFailed("Database is unavailable")
        }
        try databaseManager.updateLiability(
            id: id,
            name: name,
            liabilityGroup: liabilityGroup,
            category: category,
            currency: currency,
            balance: balance,
            interestRate: interestRate
        )
        refreshLiabilities()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var databaseManager: DatabaseManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--fintrack-snapshot") {
            SnapshotBackgroundAgent.run()
            NSApp.terminate(nil)
            return
        }
        if CommandLine.arguments.contains("--fintrack-today-baseline") {
            Task {
                await TodayBaselineBackgroundAgent.run()
                NSApp.terminate(nil)
            }
            return
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        initializeDatabase()
        SnapshotScheduler.install()
        configureWindows()
    }

    private func initializeDatabase() {
        do {
            databaseManager = try DatabaseManager()
        } catch {
            NSLog("FinTrack database initialization failed: %@", error.localizedDescription)
        }
    }

    private func configureWindows() {
        for window in NSApp.windows {
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
        }
    }
}

private enum SnapshotBackgroundAgent {
    static func run() {
        do {
            let databaseManager = try DatabaseManager()
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            let snapshotDate = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
            let dateString = formatter.string(from: snapshotDate)
            guard !(try databaseManager.listSnapshots()).contains(where: { $0.date == dateString }) else {
                return
            }
            try databaseManager.saveSnapshot(
                date: dateString,
                assets: try databaseManager.assetTotals(),
                liabilities: try databaseManager.liabilityTotals(),
                detailValues: (try? databaseManager.snapshotDetailValues()) ?? [:]
            )
        } catch {
            NSLog("FinTrack background snapshot failed: %@", error.localizedDescription)
        }
    }
}

private enum TodayBaselineBackgroundAgent {
    static func run() async {
        do {
            let databaseManager = try DatabaseManager()
            let holdings = try databaseManager.listHoldings()
            let client = MarketDataClient()
            var quotes: [(DatabaseManager.HoldingRecord, MarketDataClient.Quote)] = []
            for holding in holdings {
                if let quote = try await client.fetchQuote(symbol: holding.symbol) {
                    quotes.append((holding, quote))
                }
            }
            guard quotes.count == holdings.count, !holdings.isEmpty else { return }

            for currency in Set(holdings.map(\.currency)).filter({ $0 != "NTD" }) {
                if let rate = try await client.fetchExchangeRate(baseCurrency: currency) {
                    try databaseManager.insertExchangeRate(
                        base: currency, quote: "NTD", rate: rate,
                        observedAt: ISO8601DateFormatter().string(from: Date()),
                        source: "ExchangeRate-API"
                    )
                }
            }
            var baselineValue = 0.0
            for (holding, quote) in quotes {
                guard let previousClose = quote.previousClose else { return }
                let rate = holding.currency == "NTD"
                    ? 1
                    : ((try databaseManager.latestExchangeRate(base: holding.currency, quote: "NTD")) ?? 0)
                guard rate > 0 else { return }
                baselineValue += previousClose * holding.shares * rate
            }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            try databaseManager.savePortfolioDailyBaseline(
                date: formatter.string(from: Date()), marketValueNTD: baselineValue
            )
        } catch {
            NSLog("FinTrack TODAY baseline failed: %@", error.localizedDescription)
        }
    }
}

private enum SnapshotScheduler {
    private static let label = "com.fintrack.snapshot"

    private static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    static func install() {
        guard let executablePath = Bundle.main.executablePath else { return }
        let configuredTime = UserDefaults.standard.string(forKey: "snapshotTime") ?? "23:00"
        let components = configuredTime.split(separator: ":").compactMap { Int($0) }
        guard components.count == 2,
              (0...23).contains(components[0]),
              (0...59).contains(components[1]) else { return }

        let launchAgent: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath, "--fintrack-snapshot"],
            "StartCalendarInterval": [
                "Hour": components[0],
                "Minute": components[1]
            ],
            "ProcessType": "Background",
            "RunAtLoad": false
        ]

        do {
            let directoryURL = launchAgentURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(
                fromPropertyList: launchAgent,
                format: .xml,
                options: 0
            )
            try data.write(to: launchAgentURL, options: .atomic)

            let domain = "gui/\(getuid())"
            runLaunchctl(["bootout", domain, launchAgentURL.path])
            runLaunchctl(["bootstrap", domain, launchAgentURL.path])
            installTodayBaselineAgent(executablePath: executablePath, domain: domain)
        } catch {
            NSLog("FinTrack snapshot scheduler setup failed: %@", error.localizedDescription)
        }
    }

    private static func installTodayBaselineAgent(executablePath: String, domain: String) {
        let url = launchAgentURL.deletingLastPathComponent().appendingPathComponent("com.fintrack.today-baseline.plist")
        let agent: [String: Any] = [
            "Label": "com.fintrack.today-baseline",
            "ProgramArguments": [executablePath, "--fintrack-today-baseline"],
            "StartCalendarInterval": ["Hour": 8, "Minute": 0],
            "ProcessType": "Background",
            "RunAtLoad": false
        ]
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: agent, format: .xml, options: 0)
            try data.write(to: url, options: .atomic)
            runLaunchctl(["bootout", domain, url.path])
            runLaunchctl(["bootstrap", domain, url.path])
        } catch {
            NSLog("FinTrack TODAY scheduler setup failed: %@", error.localizedDescription)
        }
    }

    private static func runLaunchctl(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            NSLog("FinTrack launchctl failed: %@", error.localizedDescription)
        }
    }
}

enum AppLanguage: String {
    case english = "en"
    case traditionalChinese = "zh-Hant"
}

private enum FinTrackTheme {
    private static func adaptive(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua ? light : dark
            return NSColor(calibratedRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }

    static let appBackground = adaptive(light: (0xF3 / 255.0, 0xF2 / 255.0, 0xEE / 255.0), dark: (0x24 / 255.0, 0x27 / 255.0, 0x26 / 255.0))
    static let sidebarBackground = adaptive(light: (0xEB / 255.0, 0xEA / 255.0, 0xE5 / 255.0), dark: (0x1E / 255.0, 0x22 / 255.0, 0x21 / 255.0))
    static let cardBackground = adaptive(light: (0xFA / 255.0, 0xF9 / 255.0, 0xF6 / 255.0), dark: (0x30 / 255.0, 0x34 / 255.0, 0x32 / 255.0))
    static let surfaceHover = adaptive(light: (0xEE / 255.0, 0xED / 255.0, 0xE8 / 255.0), dark: (0x38 / 255.0, 0x3D / 255.0, 0x3A / 255.0))
    static let border = adaptive(light: (0xD1 / 255.0, 0xD2 / 255.0, 0xCD / 255.0), dark: (0x50 / 255.0, 0x56 / 255.0, 0x52 / 255.0))
    static let divider = adaptive(light: (0xDD / 255.0, 0xDD / 255.0, 0xD8 / 255.0), dark: (0x45 / 255.0, 0x4A / 255.0, 0x47 / 255.0))
    static let textPrimary = adaptive(light: (0x29 / 255.0, 0x2D / 255.0, 0x2B / 255.0), dark: (0xF0 / 255.0, 0xEE / 255.0, 0xE9 / 255.0))
    static let textSecondary = adaptive(light: (0x5F / 255.0, 0x64 / 255.0, 0x61 / 255.0), dark: (0xB8 / 255.0, 0xB6 / 255.0, 0xB0 / 255.0))
    static let textMuted = adaptive(light: (0x7C / 255.0, 0x81 / 255.0, 0x7E / 255.0), dark: (0x91 / 255.0, 0x93 / 255.0, 0x8E / 255.0))
    static let textDisabled = adaptive(light: (0xA1 / 255.0, 0xA3 / 255.0, 0x9F / 255.0), dark: (0x6F / 255.0, 0x72 / 255.0, 0x6E / 255.0))
    static let primary = adaptive(light: (0x58 / 255.0, 0x7D / 255.0, 0x8D / 255.0), dark: (0x83 / 255.0, 0xA6 / 255.0, 0xB5 / 255.0))
    static let primaryHover = adaptive(light: (0x48 / 255.0, 0x6C / 255.0, 0x7C / 255.0), dark: (0x96 / 255.0, 0xB6 / 255.0, 0xC3 / 255.0))
    static let primaryActive = adaptive(light: (0x3E / 255.0, 0x60 / 255.0, 0x6E / 255.0), dark: (0x71 / 255.0, 0x93 / 255.0, 0xA2 / 255.0))
    static let primaryMuted = adaptive(light: (0xDD / 255.0, 0xE7 / 255.0, 0xEA / 255.0), dark: (0x34 / 255.0, 0x4A / 255.0, 0x52 / 255.0))
    static let positive = adaptive(light: (0x52 / 255.0, 0x7A / 255.0, 0x60 / 255.0), dark: (0x88 / 255.0, 0xB4 / 255.0, 0x9A / 255.0))
    static let positiveMuted = adaptive(light: (0x6E / 255.0, 0x90 / 255.0, 0x77 / 255.0), dark: (0x70 / 255.0, 0x9A / 255.0, 0x80 / 255.0))
    static let negative = adaptive(light: (0x9B / 255.0, 0x5E / 255.0, 0x59 / 255.0), dark: (0xC1 / 255.0, 0x84 / 255.0, 0x7F / 255.0))
    static let negativeMuted = adaptive(light: (0xAD / 255.0, 0x77 / 255.0, 0x72 / 255.0), dark: (0xA3 / 255.0, 0x6F / 255.0, 0x6B / 255.0))
    static let warning = adaptive(light: (0x8B / 255.0, 0x6D / 255.0, 0x38 / 255.0), dark: (0xC9 / 255.0, 0xAA / 255.0, 0x72 / 255.0))
    static let info = primary
    static let logoContainerBackground = adaptive(light: (0xEE / 255.0, 0xED / 255.0, 0xE8 / 255.0), dark: (0x37 / 255.0, 0x3B / 255.0, 0x39 / 255.0))
    static let logoContainerHover = adaptive(light: (0xE5 / 255.0, 0xE4 / 255.0, 0xDF / 255.0), dark: (0x3E / 255.0, 0x43 / 255.0, 0x40 / 255.0))
    static let logoContainerBorder = adaptive(light: (0xD1 / 255.0, 0xD2 / 255.0, 0xCD / 255.0), dark: (0x50 / 255.0, 0x55 / 255.0, 0x52 / 255.0))
    static let logoFallbackBackground = adaptive(light: (0xDD / 255.0, 0xE7 / 255.0, 0xEA / 255.0), dark: (0x32 / 255.0, 0x46 / 255.0, 0x4D / 255.0))
    static let logoFallbackBorder = adaptive(light: (0xC4 / 255.0, 0xD3 / 255.0, 0xD8 / 255.0), dark: (0x49 / 255.0, 0x61 / 255.0, 0x6A / 255.0))
    static let logoFallbackForeground = adaptive(light: (0x58 / 255.0, 0x7D / 255.0, 0x8D / 255.0), dark: (0x96 / 255.0, 0xB6 / 255.0, 0xC3 / 255.0))

    static let allocationPalette = [
        adaptive(light: (0x6F / 255.0, 0x92 / 255.0, 0x9F / 255.0), dark: (0x8B / 255.0, 0xA9 / 255.0, 0xB5 / 255.0)),
        adaptive(light: (0x55 / 255.0, 0x76 / 255.0, 0x83 / 255.0), dark: (0x6F / 255.0, 0x8D / 255.0, 0x98 / 255.0)),
        adaptive(light: (0x66 / 255.0, 0x87 / 255.0, 0x7E / 255.0), dark: (0x78 / 255.0, 0x96 / 255.0, 0x8E / 255.0)),
        adaptive(light: (0x50 / 255.0, 0x6F / 255.0, 0x69 / 255.0), dark: (0x65 / 255.0, 0x7D / 255.0, 0x78 / 255.0)),
        adaptive(light: (0xB5 / 255.0, 0x8D / 255.0, 0x49 / 255.0), dark: (0xD0 / 255.0, 0xAC / 255.0, 0x6C))
    ]
}

private enum CompanyLogoRepository {
    private static let maxCacheBytes = 50 * 1024 * 1024
    private static let refreshInterval: TimeInterval = 30 * 24 * 60 * 60

    static func data(for symbol: String) async -> Data? {
        let fileURL = cacheURL(for: symbol)
        let cachedData = try? Data(contentsOf: fileURL)
        if let cachedData,
           let modified = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           Date().timeIntervalSince(modified) < refreshInterval {
            return cachedData
        }

        do {
            let encodedSymbol = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
            guard let url = URL(string: "https://financialmodelingprep.com/image-stock/\(encodedSymbol).png") else {
                return cachedData
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  NSImage(data: data) != nil else {
                return cachedData
            }
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            trimCache()
            return data
        } catch {
            return cachedData
        }
    }

    private static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FinTrack/CompanyLogos", isDirectory: true)
    }

    private static func cacheURL(for symbol: String) -> URL {
        let safeName = symbol.map { $0.isLetter || $0.isNumber ? $0 : "_" }
        return cacheDirectory.appendingPathComponent(String(safeName) + ".png")
    }

    private static func trimCache() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return }

        let entries = files.compactMap { url -> (url: URL, size: Int, modified: Date)? in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize,
                  let modified = values.contentModificationDate else { return nil }
            return (url, size, modified)
        }
        var total = entries.reduce(0) { $0 + $1.size }
        for entry in entries.sorted(by: { $0.modified < $1.modified }) where total > maxCacheBytes {
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
    }
}

@MainActor
private final class CompanyLogoLoader: ObservableObject {
    let symbol: String
    @Published var image: NSImage?

    init(symbol: String) {
        self.symbol = symbol
    }

    func load() async {
        guard image == nil, !symbol.isEmpty else { return }
        guard let data = await CompanyLogoRepository.data(for: symbol), !Task.isCancelled else { return }
        image = NSImage(data: data)
    }
}

private struct CompanyLogoView: View {
    let symbol: String
    let name: String
    @StateObject private var loader: CompanyLogoLoader

    init(symbol: String, name: String) {
        self.symbol = symbol
        self.name = name
        _loader = StateObject(wrappedValue: CompanyLogoLoader(symbol: symbol))
    }

    var body: some View {
        Group {
            if let image = loader.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(8)
                    .accessibilityHidden(true)
            } else {
                Text(fallbackInitial)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(FinTrackTheme.logoFallbackForeground)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 48, height: 48)
        .background {
            if loader.image == nil {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(FinTrackTheme.logoFallbackBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(FinTrackTheme.logoFallbackBorder, lineWidth: 1)
                    }
            }
        }
        .accessibilityHidden(true)
        .task(id: symbol) {
            await loader.load()
        }
    }

    private var fallbackInitial: String {
        let meaningfulName = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .first
        return String(meaningfulName?.first ?? symbol.first ?? "?").uppercased()
    }
}

enum L10n {
    private static let traditionalChinese: [String: String] = [
        "Overview": "總覽", "Income Statement": "損益表", "Portfolio": "投資組合", "Dividends": "股利",
        "Recurring Investment": "定期定額", "Recurring Rules": "定期定額規則", "Click to view investments": "點擊查看投資紀錄", "Foreign Currency": "外幣", "Stock": "股票",
        "Total NTD Equivalent": "新台幣等價總額", "Currencies Held": "持有幣別", "Rates Updated": "匯率更新", "Latest Rate": "最新匯率",
        "live exchange rates": "即時匯率", "ExchangeRate-API": "ExchangeRate-API", "converted from foreign-currency balances": "由外幣餘額換算",
        "BALANCE": "餘額", "RATE": "匯率", "NTD VALUE": "新台幣等價", "CURRENCY": "幣別", "SECURITY": "標的", "DATE": "日期", "AMOUNT": "金額", "TRANSACTIONS": "交易紀錄", "PURPOSE": "用途", "FOREIGN": "原幣", "NTD": "新台幣", "SHARES": "股數",
        "Add foreign-currency transaction": "新增外幣交易", "Transaction type": "交易類型", "Exchange": "換匯", "Exchange direction": "換匯方向", "Buy foreign currency": "買入外幣", "Sell foreign currency back to NTD": "賣出外幣換回新台幣", "Other purpose": "其他用途", "Original currency": "原幣別", "Foreign amount": "原幣金額", "Foreign amount (+ income / - expense)": "原幣金額（收入＋／支出－）", "NTD amount": "新台幣金額", "Rate (NTD per unit)": "匯率（每單位新台幣）", "NTD amount (exchange only)": "新台幣金額（僅換匯）", "Rate (NTD per unit, exchange only)": "匯率（每單位新台幣，僅換匯）", "Purpose": "用途", "Date": "日期", "Exchange transactions require NTD amount and rate.": "換匯交易需要填寫新台幣金額與匯率。", "Other transactions only change the foreign-currency balance; NTD amount and rate are not required.": "其他交易只會變更外幣餘額，不需要填寫新台幣金額與匯率。", "Enter a currency and positive foreign amount.": "請輸入幣別與正的原幣金額。", "Enter a purpose, currency, and positive foreign amount.": "請輸入用途、幣別與正的原幣金額。", "Enter a valid NTD amount and rate for an exchange.": "請輸入有效的新台幣金額與匯率。", "Use a negative foreign amount for investments, spending, or exchanging foreign currency back to NTD. Leave NTD and rate blank for non-exchange transactions.": "投資、支出或換回新台幣時，原幣金額請填負值；非換匯交易的新台幣與匯率請留空。", "Enter a purpose, currency, and non-zero foreign amount.": "請輸入用途、幣別與非零的原幣金額。", "Enter both NTD amount and rate, or leave both blank.": "請同時輸入新台幣金額與匯率，或兩者都留空。", "NTD amount and rate must be greater than zero.": "新台幣金額與匯率必須大於零。",
        "ETF": "ETF", "Settings": "設定", "Help": "說明", "Add": "新增",
        "No recurring investments": "目前沒有定期定額", "No recurring rules": "目前沒有定期定額規則", "Add a rule to plan your recurring investments.": "新增規則以規劃定期定額投資。",
        "No market prices": "尚無市場價格", "Updating market prices": "正在更新市場價格", "NTD converted": "已換算新台幣", "holdings": "筆持股", "shares": "股", "purchases": "筆投資", "monthly": "每月", "day": "日", "currency": "幣別", "currencies": "種幣別", "No foreign-currency balances recorded.": "目前沒有外幣餘額。", "No foreign-currency transactions recorded.": "目前沒有外幣交易紀錄。", "MARKET VALUE": "目前市值",
        "TOTAL CONTRIBUTED": "累計投入", "TOTAL SHARES": "總股數", "LAST PURCHASE": "最近投資", "SCHEDULES": "排程", "PURCHASES": "投資紀錄", "No purchases recorded. Click + to add the actual transaction.": "尚無投資紀錄，請按＋新增實際交易。",
        "No holdings yet. Click Add to create one.": "目前沒有持股，請按新增建立。",
        "Allocation will appear after holdings and market prices are available.": "建立持股並取得市場價格後，這裡會顯示資產配置。",
        "Total Assets": "總資產", "Total Liabilities": "總負債", "Net Worth": "淨值",
        "Total Assets Details": "總資產明細", "Total Liabilities Details": "總負債明細",
        "Liquid Asset": "流動資產", "Liquid Investment": "流動性投資", "Long-term Investment": "長期投資", "Other Asset": "其他資產",
        "Liquid Assets": "流動資產", "Liquid Investments": "流動性投資", "Other Assets": "其他資產",
        "Short-term Liabilities": "短期負債", "Long-term Liabilities": "長期負債",
        "Bank Accounts": "銀行帳戶", "Cash": "現金", "Margin Deposit": "期貨保證金",
        "U.S. Stocks": "美股", "U.S. ETFs": "美股 ETF", "Taiwan ETFs": "台股 ETF",
        "Retirement Fund": "勞退基金", "House Deposit": "房屋押金", "Other": "其他",
        "Financial Indicators": "財務指數", "Free Cash Flow": "自由現金流量", "Liability Ratio": "負債比率",
        "Cash Ratio": "現金比率", "Equity Multiplier": "權益乘數", "Net Worth Growth Rate": "淨值成長率",
        "Net Worth History": "淨值歷史", "Chart area — to be connected to snapshots": "圖表區域 — 將連接資產快照", "Use the sidebar to switch between your financial sections. Market prices and exchange rates are refreshed when the relevant page is opened.": "使用左側邊欄切換財務區塊；開啟相關頁面時會更新股價與匯率。",
        "Overview Guide": "總覽使用說明", "Understand your overall financial position.": "了解你的整體財務狀況。", "OVERVIEW": "總覽", "Your financial picture": "你的財務全貌", "Overview brings your assets, liabilities, investments, and cash together in one financial snapshot.": "總覽會把你的資產、負債、投資與現金集中在同一個財務快照中。", "KEY METRICS": "重要數字", "Everything you currently own, converted to NTD.": "你目前擁有的所有資產，並換算成新台幣。", "Money you currently owe.": "你目前需要償還的金額。", "Total Assets − Total Liabilities": "總資產 − 總負債", "YOUR DETAILS": "你的資產明細", "Cash and other readily available funds.": "現金及其他可以立即使用的資金。", "Investments that can generally be sold.": "通常可以出售變現的投資。", "Assets intended to be held longer.": "預計持有較長時間的資產。", "CHANGES OVER TIME": "查看變化", "Compares the current value with the previous month. You can hide these percentages in Settings.": "比較目前數值與上個月的差異，也可以在設定中關閉百分比。", "ADDING INFORMATION": "新增資料", "Add an asset or liability": "新增資產或負債", "Use the + button in the corresponding details section.": "使用對應明細區塊旁的＋按鈕。", "Add investments": "新增投資", "Open Portfolio from the sidebar.": "從左側邊欄開啟投資組合。", "Add foreign currency": "新增外幣", "Open Foreign Currency from the sidebar.": "從左側邊欄開啟外幣。", "Market data": "市場資料", "FinTrack refreshes market prices and exchange rates when possible. Saved local data remains available offline.": "FinTrack 會在可行時更新市場價格與匯率；沒有網路時，仍可使用已儲存的本機資料。",
        "Income": "收入", "Expenses": "支出", "Savings": "儲蓄", "Salary": "薪資",
        "Bonus": "獎金", "Side Income": "副業收入", "Base Salary": "本薪", "Overtime": "加班費",
        "Freelance": "接案收入", "Necessary": "必要開銷", "Credit Card": "信用卡", "Loan": "貸款", "Mortgage": "房屋貸款", "Auto Loan": "車貸", "Personal Loan": "個人貸款", "Tax Payable": "稅款／應付款", "Daily Expenses": "日常花費",
        "Student Loan": "學貸", "Rent": "房租", "Utilities": "水電瓦斯網路", "Living Expenses": "生活費",
        "Principal": "本金", "Interest": "利息", "Apartment": "房租", "Electricity": "電費",
        "Internet": "網路費", "Food": "餐費", "Transportation": "交通費", "Investment": "投資金",
        "Emergency Fund": "緊急預備金", "Cash Reserve": "現金預留", "Stocks": "股票", "Monthly Reserve": "每月預留",
        "ETFs": "ETF", "High-yield Savings": "高利活存", "TOTAL P&L": "總損益", "TODAY": "今日", "vs previous close": "相較前一日收盤",
        "INVESTED": "投入成本", "HOLDINGS": "持有資產", "SYMBOL": "標的", "LAST": "現價",
        "CHANGE": "變化", "VALUE": "市值", "P&L": "損益", "ALLOCATION": "資產配置",
        "ASSETS": "資產", "ETFs 57%": "ETF 57%", "Stocks 43%": "股票 43%",
        "About": "關於", "Version": "版本",
        "Display": "顯示", "Show detail percentage changes": "顯示明細百分比變化", "Performance colors": "漲跌顏色", "Green up / red down": "綠漲紅跌", "Red up / green down": "紅漲綠跌", "Analog mode": "類比模式", "Daily snapshot time": "每日快照時間", "Appearance": "外觀", "System": "跟隨系統", "Light": "淺色", "Dark": "深色", "Total Income": "總收入", "Total Expenses": "總支出", "Monthly Profit": "月結餘", "Account Allocation": "帳戶配置", "Account allocation will appear after leaf items are added.": "新增明細項目後，這裡會顯示帳戶配置。", "No items yet. Click + to add one.": "目前沒有項目，請按＋新增。", "Add child": "新增子項目", "Edit": "編輯", "Delete": "刪除", "Add item": "新增項目", "Edit item": "編輯項目", "Item name": "項目名稱", "Destination account (optional)": "轉入帳戶（選填）", "Use existing account": "使用既有帳戶", "No linked account": "不連結帳戶", "Leaf items can share a destination account. Parent items with children are totaled from their children.": "最底層項目可共用轉入帳戶；有子項目的父項目會依子項目加總。",
        "Turn this off to hide month-over-month percentages in asset and liability details.": "關閉後，資產與負債明細將隱藏月增減百分比。",
        "Language": "語言", "English": "英文", "Traditional Chinese": "繁體中文", "Total": "合計",
        "Add Asset": "新增資產", "Asset name": "資產名稱", "Asset Name": "資產名稱",
        "Category": "分類", "Asset group": "資產分類", "Subcategory": "子分類", "Currency": "幣別", "Amount (NTD)": "金額（新台幣）",
        "Original amount": "原幣金額", "Initial NTD cost": "初始新台幣成本", "Current balance cost basis (NTD)": "目前餘額成本基礎（新台幣）", "Average exchange rate": "平均匯率",
        "Only exchange or opening-fund cost is included. Dividends and investment gains are recorded separately.": "只有換匯或初始入金成本會計入；股息與投資收益會獨立記錄。",
        "Cancel": "取消", "Save": "儲存", "Add Liability": "新增負債", "Liability name": "負債名稱",
        "Group": "負債分類", "Balance": "餘額", "Interest rate (optional)": "利率（選填）",
        "Short-term Liability": "短期負債", "Long-term Liability": "長期負債", "Add holding": "新增持股"
    ]

    static func text(_ key: String, language: String) -> String {
        guard language == AppLanguage.traditionalChinese.rawValue else { return key }
        return traditionalChinese[key] ?? key
    }
}

struct DashboardView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedPage = "Overview"
    @State private var helpPage = "Overview"
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @State private var activeAppearanceMode = "system"
    @State private var resolvedSystemScheme: ColorScheme = .dark

    private var preferredColorScheme: ColorScheme? {
        switch activeAppearanceMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedPage: $selectedPage)
                .navigationSplitViewColumnWidth(min: 240, ideal: 240, max: 240)
        } detail: {
            ZStack(alignment: .topTrailing) {
                DashboardContentView(
                    pageTitle: selectedPage,
                    helpPage: helpPage,
                    selectedPage: $selectedPage,
                    appearanceMode: $activeAppearanceMode
                )
                Button {
                    helpPage = selectedPage
                    selectedPage = "Help"
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .help("Help")
                .padding(.top, 14)
                .padding(.trailing, 20)
            }
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            .background(FinTrackTheme.appBackground.ignoresSafeArea())
        }
        .navigationSplitViewStyle(.prominentDetail)
        .frame(minWidth: 980, minHeight: 680)
        .background(FinTrackTheme.appBackground.ignoresSafeArea())
        .foregroundStyle(FinTrackTheme.textPrimary)
        .tint(FinTrackTheme.primary)
        .preferredColorScheme(preferredColorScheme)
        .environment(\.colorScheme, activeAppearanceMode == "system" ? resolvedSystemScheme : (activeAppearanceMode == "light" ? .light : .dark))
        .onAppear {
            hideWindowTitle()
            activeAppearanceMode = appearanceMode
            applyAppearance(activeAppearanceMode)
        }
        .onChange(of: activeAppearanceMode) { _, newMode in
            appearanceMode = newMode
            applyAppearance(newMode)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await appModel.refreshMarketData() }
        }
    }

    private func applyAppearance(_ mode: String) {
        let appearance: NSAppearance?
        switch mode {
        case "light":
            appearance = NSAppearance(named: .aqua)
        case "dark":
            appearance = NSAppearance(named: .darkAqua)
        default:
            appearance = nil
        }
        NSApp.appearance = appearance
        NSApp.windows.forEach { $0.appearance = appearance }
        if mode == "system" {
            let systemStyle = UserDefaults.standard.string(forKey: "AppleInterfaceStyle")?.lowercased()
            resolvedSystemScheme = systemStyle == "dark" ? .dark : .light
        } else {
            resolvedSystemScheme = mode == "light" ? .light : .dark
        }
    }

    private func hideWindowTitle() {
        for window in NSApp.windows {
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
        }
    }
}

struct SidebarView: View {
    @Binding var selectedPage: String
    @EnvironmentObject private var appModel: AppModel
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    @State private var recurringExpanded = false

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        List {
            Section {
                page("Overview", systemImage: "square.grid.2x2")
                page("Portfolio", systemImage: "chart.pie")
                page("Dividends", systemImage: "banknote")

                expandablePage("Recurring Investment", systemImage: "calendar.badge.clock", isExpanded: $recurringExpanded)
                if recurringExpanded {
                    if appModel.recurringRecords.isEmpty {
                        Text(L10n.text("No recurring investments", language: appLanguage))
                            .foregroundStyle(FinTrackTheme.textSecondary)
                            .padding(.leading, 22)
                    } else {
                        ForEach(appModel.recurringRecords) { recurring in
                            page(recurring.securityName, systemImage: "chart.bar.xaxis", isChild: true)
                        }
                    }
                }

                page("Foreign Currency", systemImage: "globe.americas.fill")
                page("Income Statement", systemImage: "chart.line.uptrend.xyaxis")
            }

        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(FinTrackTheme.sidebarBackground)
        .safeAreaInset(edge: .top) {
            HStack {
                Text("FinTrack")
                    .font(.title2.weight(.bold))
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 14) {
                SidebarIconButton(systemImage: "gearshape", isSelected: false) {
                    selectedPage = "Settings"
                }
                Spacer()
                Text("v\(appVersion)")
                    .font(.caption2)
                    .foregroundStyle(FinTrackTheme.textSecondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(FinTrackTheme.sidebarBackground)
        }
    }

    private func page(
        _ title: String,
        systemImage: String,
        isChild: Bool = false
    ) -> some View {
        HStack(spacing: 8) {
            Label(L10n.text(title, language: appLanguage), systemImage: systemImage)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(selectedPage == title ? .headline.weight(.semibold) : .body)
        .foregroundStyle(selectedPage == title ? FinTrackTheme.primaryHover : FinTrackTheme.textPrimary)
        .padding(.leading, isChild ? 22 : 0)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            selectedPage == title ? FinTrackTheme.primaryMuted : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .scaleEffect(selectedPage == title ? 1.04 : 1, anchor: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { selectedPage = title }
    }

    private func expandablePage(
        _ title: String,
        systemImage: String,
        isExpanded: Binding<Bool>
    ) -> some View {
        HStack(spacing: 8) {
            Label(L10n.text(title, language: appLanguage), systemImage: systemImage)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(selectedPage == title ? .headline.weight(.semibold) : .body)
        .foregroundStyle(selectedPage == title ? FinTrackTheme.primaryHover : FinTrackTheme.textPrimary)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            selectedPage == title ? FinTrackTheme.primaryMuted : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .scaleEffect(selectedPage == title ? 1.04 : 1, anchor: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            if selectedPage == title {
                isExpanded.wrappedValue.toggle()
            } else {
                selectedPage = title
                isExpanded.wrappedValue = true
            }
        }
    }

}

struct SidebarIconButton: View {
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 28, height: 28)
                .foregroundStyle(isSelected ? FinTrackTheme.textPrimary : FinTrackTheme.textSecondary)
                .background(
                    isSelected ? FinTrackTheme.primary : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
        }
        .buttonStyle(.plain)
    }
}

struct DashboardContentView: View {
    let pageTitle: String
    let helpPage: String
    @Binding var selectedPage: String
    @Binding var appearanceMode: String
    @EnvironmentObject private var appModel: AppModel
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    @AppStorage("showDetailChanges") private var showDetailChanges = false
    @AppStorage("showDetailChangesInitialized") private var showDetailChangesInitialized = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if pageTitle != "Help" {
                Text(L10n.text(pageTitle, language: appLanguage))
                    .font(.largeTitle.weight(.bold))
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
            }

            if pageTitle == "Portfolio" {
                PortfolioView()
            } else if pageTitle == "Dividends" {
                DividendManagementView()
            } else if pageTitle == "Recurring Investment" {
                RecurringInvestmentView(selectedPage: $selectedPage)
            } else if pageTitle == "Foreign Currency" {
                ForeignCurrencyView()
            } else if let recurring = appModel.recurringRecords.first(where: { $0.securityName == pageTitle }) {
                ScrollView {
                    RecurringHoldingDetailView(rule: recurring)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if pageTitle == "Income Statement" {
                IncomeStatementView()
            } else if pageTitle == "Settings" {
                ScrollView {
                    SettingsCard(showDetailChanges: $showDetailChanges, appearanceMode: $appearanceMode)
                        .padding(24)
                }
            } else if pageTitle == "Help" {
                HelpView(page: helpPage) {
                    selectedPage = helpPage
                }
            } else {
                OverviewView(showChanges: showDetailChanges)
            }
        }
        .background(FinTrackTheme.appBackground)
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            appModel.startMarketPriceStream()
            if !showDetailChangesInitialized {
                showDetailChanges = false
                showDetailChangesInitialized = true
            }
        }
    }
}

private struct CurrencyBadge: View {
    let code: String

    private var flag: String? {
        switch code.uppercased() {
        case "USD": return "🇺🇸"
        case "JPY": return "🇯🇵"
        case "EUR": return "🇪🇺"
        case "GBP": return "🇬🇧"
        case "AUD": return "🇦🇺"
        case "CAD": return "🇨🇦"
        case "HKD": return "🇭🇰"
        case "CNY": return "🇨🇳"
        case "KRW": return "🇰🇷"
        case "SGD": return "🇸🇬"
        case "CHF": return "🇨🇭"
        case "NZD": return "🇳🇿"
        default: return nil
        }
    }

    var body: some View {
        Group {
            if let flag {
                Text(flag)
                    .font(.title3)
            } else {
                Text(String(code.prefix(1)))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(FinTrackTheme.primary)
            }
        }
        .frame(width: 30, height: 30)
        .accessibilityLabel(Text(code))
    }
}

struct ForeignCurrencyView: View {
    private enum CurrencySortKey {
        case currency
        case ntdValue
    }

    @EnvironmentObject private var appModel: AppModel
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    @State private var showingAdd = false
    @State private var showingAddTransaction = false
    @State private var editingAsset: DatabaseManager.AssetRecord?
    @State private var pendingDelete: ForeignCurrencySummary?
    @State private var pendingDeleteTransaction: DatabaseManager.ForeignCurrencyTransactionRecord?
    @State private var sortKey: CurrencySortKey = .currency
    @State private var sortAscending = true

    private var summaries: [ForeignCurrencySummary] {
        let grouped = Dictionary(grouping: appModel.assets.filter { $0.currency != "NTD" }, by: \.currency)
        return grouped.map { currency, assets in
            let amount = assets.reduce(0) { $0 + $1.value }
            let rate = appModel.foreignExchangeRates[currency]
            let ntdValue = rate.map { amount * $0 } ?? assets.reduce(0) { $0 + $1.ntdValue }
            return ForeignCurrencySummary(
                currency: currency,
                amount: amount,
                ntdValue: ntdValue,
                rate: rate ?? (amount > 0 ? ntdValue / amount : nil),
                assetIDs: assets.map(\.id)
            )
        }
        .sorted { lhs, rhs in
            switch sortKey {
            case .currency:
                let comparison = lhs.currency.localizedCaseInsensitiveCompare(rhs.currency)
                return sortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
            case .ntdValue:
                if lhs.ntdValue != rhs.ntdValue {
                    return sortAscending ? lhs.ntdValue < rhs.ntdValue : lhs.ntdValue > rhs.ntdValue
                }
                return lhs.currency < rhs.currency
            }
        }
    }

    var body: some View {
        let totalNTD = summaries.reduce(0) { $0 + $1.ntdValue }
        let currencyCount = summaries.count

        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    foreignMetricCards(totalNTD: totalNTD, currencyCount: currencyCount)
                }
                VStack(alignment: .leading, spacing: 16) {
                    foreignMetricCards(totalNTD: totalNTD, currencyCount: currencyCount)
                }
            }
            .padding(.horizontal, 24)

            Rectangle()
                .fill(FinTrackTheme.divider)
                .frame(height: 1)
                .padding(.horizontal, 24)
                .padding(.vertical, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button(action: { showingAdd = true }) {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.plain)
                        .font(.title3.weight(.semibold))
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 16)
                    .padding(.bottom, 10)

                    HStack(spacing: 16) {
                        Button(action: { toggleSort(.currency) }) {
                            HStack(spacing: 6) {
                                Text(L10n.text("CURRENCY", language: appLanguage))
                                sortIndicator(for: .currency)
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(L10n.text("BALANCE", language: appLanguage)).frame(width: 150, alignment: .trailing)
                        Text(L10n.text("RATE", language: appLanguage)).frame(width: 150, alignment: .trailing)
                        Button(action: { toggleSort(.ntdValue) }) {
                            HStack(spacing: 6) {
                                sortIndicator(for: .ntdValue)
                                Text(L10n.text("NTD VALUE", language: appLanguage))
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 170, alignment: .trailing)
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(FinTrackTheme.textSecondary)
                    .padding(.horizontal, 40)
                    .padding(.top, 8)
                    .padding(.bottom, 10)

                    if summaries.isEmpty {
                        Text(L10n.text("No foreign-currency balances recorded.", language: appLanguage))
                            .foregroundStyle(FinTrackTheme.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 180)
                    } else {
                        ForEach(sortedSummaries) { summary in
                            HStack(spacing: 16) {
                                HStack(spacing: 10) {
                                    CurrencyBadge(code: summary.currency)
                                    Text(summary.currency)
                                        .font(.headline)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Text(money(summary.amount, currency: summary.currency))
                                    .frame(width: 150, alignment: .trailing)
                                Text(summary.rate.map { String(format: "NTD %.4f", $0) } ?? "—")
                                    .frame(width: 150, alignment: .trailing)
                                Text(ntd(summary.ntdValue))
                                    .font(.headline)
                                    .frame(width: 170, alignment: .trailing)
                            }
                            .padding(.horizontal, 40)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button("Edit") {
                                    editingAsset = appModel.assets.first { $0.currency == summary.currency }
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    pendingDelete = summary
                                }
                            }
                        }
                    }
                }
                .background(FinTrackTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(FinTrackTheme.border))

                foreignTransactionCard
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            await appModel.refreshForeignExchangeRates()
        }
        .sheet(isPresented: $showingAdd) {
            AddForeignCurrencySheet()
        }
        .sheet(isPresented: $showingAddTransaction) {
            ForeignCurrencyTransactionSheet()
        }
        .sheet(item: $editingAsset) { asset in
            EditAssetSheet(asset: asset)
        }
        .alert(item: $pendingDelete) { summary in
            Alert(
                title: Text("Delete \(summary.currency)?"),
                message: Text("This will remove the recorded balance for this currency."),
                primaryButton: .destructive(Text("Delete")) {
                    for id in summary.assetIDs {
                        appModel.deleteAsset(id: id)
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .alert(item: $pendingDeleteTransaction) { transaction in
            Alert(
                title: Text("Delete transaction?"),
                message: Text("This will also reverse its effect on the foreign-currency balance."),
                primaryButton: .destructive(Text("Delete")) {
                    appModel.deleteForeignCurrencyTransaction(id: transaction.id)
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var sortedSummaries: [ForeignCurrencySummary] {
        summaries
    }

    private func toggleSort(_ key: CurrencySortKey) {
        if sortKey == key {
            sortAscending.toggle()
        } else {
            sortKey = key
            sortAscending = true
        }
    }

    @ViewBuilder
    private func sortIndicator(for key: CurrencySortKey) -> some View {
        if sortKey == key {
            Image(systemName: sortAscending ? "arrow.down" : "arrow.up")
                .font(.caption2)
        }
    }

    private var foreignTransactionCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L10n.text("TRANSACTIONS", language: appLanguage))
                    .font(.title3.weight(.semibold))
                Spacer()
                Button(action: { showingAddTransaction = true }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .font(.title3.weight(.semibold))
            }
            .padding(.horizontal, 40)
            .padding(.top, 18)
            .padding(.bottom, 14)

            LazyVGrid(columns: transactionGridColumns, alignment: .leading, spacing: 0) {
                Text(L10n.text("PURPOSE", language: appLanguage)).frame(maxWidth: .infinity, alignment: .leading)
                Text(L10n.text("CURRENCY", language: appLanguage)).frame(maxWidth: .infinity, alignment: .leading)
                Text(L10n.text("FOREIGN", language: appLanguage)).frame(maxWidth: .infinity, alignment: .trailing)
                Text(L10n.text("NTD", language: appLanguage)).frame(maxWidth: .infinity, alignment: .trailing)
                Text(L10n.text("RATE", language: appLanguage)).frame(maxWidth: .infinity, alignment: .trailing)
                Text(L10n.text("DATE", language: appLanguage)).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(FinTrackTheme.textSecondary)
            .padding(.horizontal, 40)
            .padding(.bottom, 10)

            if appModel.foreignCurrencyTransactions.isEmpty {
                Text(L10n.text("No foreign-currency transactions recorded.", language: appLanguage))
                    .foregroundStyle(FinTrackTheme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                ForEach(appModel.foreignCurrencyTransactions) { transaction in
                    LazyVGrid(columns: transactionGridColumns, alignment: .leading, spacing: 0) {
                        Text(transaction.purpose)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(transaction.currency)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(money(transaction.foreignAmount, currency: transaction.currency))
                            .foregroundStyle(transaction.foreignAmount < 0 ? FinTrackTheme.negative : FinTrackTheme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(transaction.ntdAmount.map(ntd) ?? "—")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(transaction.rate.map { String(format: "NTD %.4f", $0) } ?? "—")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(transaction.tradeDate)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button(L10n.text("Delete", language: appLanguage), role: .destructive) {
                            pendingDeleteTransaction = transaction
                        }
                    }
                }
            }
        }
        .background(FinTrackTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(FinTrackTheme.border))
    }

    private var transactionGridColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 140), alignment: .leading),
            GridItem(.fixed(60), alignment: .leading),
            GridItem(.fixed(110), alignment: .trailing),
            GridItem(.fixed(72), alignment: .trailing),
            GridItem(.fixed(88), alignment: .trailing),
            GridItem(.fixed(100), alignment: .trailing)
        ]
    }

    @ViewBuilder
    private func foreignMetricCards(totalNTD: Double, currencyCount: Int) -> some View {
        PortfolioMetricCard(
            title: "Total NTD Equivalent",
            value: ntd(totalNTD),
            detail: L10n.text("converted from foreign-currency balances", language: appLanguage),
            tint: .primary,
            height: 100
        )
        PortfolioMetricCard(
            title: "Currencies Held",
            value: "\(currencyCount)",
            detail: L10n.text(currencyCount == 1 ? "currency" : "currencies", language: appLanguage),
            tint: .primary,
            height: 100
        )
    }
}

private struct ForeignCurrencyTransactionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    @State private var transactionType = "exchange"
    @State private var exchangeDirection = "buy"
    @State private var otherPurpose = ""
    @State private var currency = ""
    @State private var foreignAmount = ""
    @State private var ntdAmount = ""
    @State private var rate = ""
    @State private var tradeDate = Date()
    @State private var errorMessage: String?

    private var currencies: [String] {
        Array(Set(appModel.assets.map(\.currency).filter { $0 != "NTD" })).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("Add foreign-currency transaction", language: appLanguage))
                .font(.title2.weight(.bold))
            Picker(L10n.text("Transaction type", language: appLanguage), selection: $transactionType) {
                Text(L10n.text("Exchange", language: appLanguage)).tag("exchange")
                Text(L10n.text("Other", language: appLanguage)).tag("other")
            }
            .pickerStyle(.segmented)

            if transactionType == "exchange" {
                Picker(L10n.text("Exchange direction", language: appLanguage), selection: $exchangeDirection) {
                    Text(L10n.text("Buy foreign currency", language: appLanguage)).tag("buy")
                    Text(L10n.text("Sell foreign currency back to NTD", language: appLanguage)).tag("sell")
                }
                .pickerStyle(.menu)
            } else {
                TextField(L10n.text("Other purpose", language: appLanguage), text: $otherPurpose)
                    .textFieldStyle(.roundedBorder)
            }

            Picker(L10n.text("Original currency", language: appLanguage), selection: $currency) {
                ForEach(currencies, id: \.self) { code in
                    Text(code).tag(code)
                }
            }
            TextField(L10n.text(transactionType == "exchange" ? "Foreign amount" : "Foreign amount (+ income / - expense)", language: appLanguage), text: $foreignAmount)
                .textFieldStyle(.roundedBorder)
            if transactionType == "exchange" {
                TextField(L10n.text("NTD amount", language: appLanguage), text: $ntdAmount)
                    .textFieldStyle(.roundedBorder)
                TextField(L10n.text("Rate (NTD per unit)", language: appLanguage), text: $rate)
                    .textFieldStyle(.roundedBorder)
            }
            DatePicker(L10n.text("Date", language: appLanguage), selection: $tradeDate, displayedComponents: .date)
            Text(L10n.text(transactionType == "exchange" ? "Exchange transactions require NTD amount and rate." : "Other transactions only change the foreign-currency balance; NTD amount and rate are not required.", language: appLanguage))
                .font(.caption)
                .foregroundStyle(FinTrackTheme.textSecondary)

            HStack {
                Spacer()
                Button(L10n.text("Cancel", language: appLanguage)) { dismiss() }
                Button(L10n.text("Save", language: appLanguage)) { save() }
                    .buttonStyle(.borderedProminent)
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(24)
        .frame(width: 500)
        .onAppear {
            if currency.isEmpty { currency = currencies.first ?? "" }
        }
    }

    private func save() {
        let trimmedPurpose = otherPurpose.trimmingCharacters(in: .whitespacesAndNewlines)
        guard transactionType == "exchange" || !trimmedPurpose.isEmpty,
              !currency.isEmpty,
              let enteredForeignValue = Double(foreignAmount), enteredForeignValue > 0 else {
            errorMessage = L10n.text(transactionType == "exchange" ? "Enter a currency and positive foreign amount." : "Enter a purpose, currency, and positive foreign amount.", language: appLanguage)
            return
        }

        let foreignValue = transactionType == "exchange" && exchangeDirection == "sell"
            ? -enteredForeignValue
            : enteredForeignValue

        let trimmedNTD = ntdAmount.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRate = rate.trimmingCharacters(in: .whitespacesAndNewlines)
        var parsedNTD = transactionType == "exchange" ? (trimmedNTD.isEmpty ? nil : Double(trimmedNTD)) : nil
        var parsedRate = trimmedRate.isEmpty ? nil : Double(trimmedRate)
        if transactionType == "exchange" {
            guard let exchangeNTD = parsedNTD, exchangeNTD > 0,
                  trimmedRate.isEmpty || parsedRate != nil else {
                errorMessage = L10n.text("Enter a valid NTD amount and rate for an exchange.", language: appLanguage)
                return
            }
            if parsedRate == nil { parsedRate = exchangeNTD / abs(foreignValue) }
            guard let exchangeRate = parsedRate, exchangeRate > 0 else {
                errorMessage = L10n.text("Enter a valid NTD amount and rate for an exchange.", language: appLanguage)
                return
            }
            parsedNTD = exchangeNTD
        } else {
            parsedNTD = nil
            parsedRate = nil
        }

        do {
            try appModel.createForeignCurrencyTransaction(
                purpose: transactionType == "exchange"
                    ? (exchangeDirection == "buy" ? "Exchange in" : "Exchange out")
                    : trimmedPurpose,
                currency: currency,
                foreignAmount: foreignValue,
                ntdAmount: parsedNTD,
                rate: parsedRate,
                tradeDate: Self.dateFormatter.string(from: tradeDate)
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct AddForeignCurrencySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    @State private var currency = ""
    @State private var balance = ""
    @State private var averageRate = ""
    @State private var errorMessage: String?

    private struct CurrencyOption: Identifiable {
        let code: String
        let englishName: String
        let chineseName: String

        var id: String { code }
    }

    private let currencyOptions: [CurrencyOption] = [
        CurrencyOption(code: "USD", englishName: "US Dollar", chineseName: "美元"),
        CurrencyOption(code: "JPY", englishName: "Japanese Yen", chineseName: "日圓"),
        CurrencyOption(code: "EUR", englishName: "Euro", chineseName: "歐元"),
        CurrencyOption(code: "GBP", englishName: "British Pound", chineseName: "英鎊"),
        CurrencyOption(code: "AUD", englishName: "Australian Dollar", chineseName: "澳幣"),
        CurrencyOption(code: "CAD", englishName: "Canadian Dollar", chineseName: "加幣"),
        CurrencyOption(code: "HKD", englishName: "Hong Kong Dollar", chineseName: "港幣"),
        CurrencyOption(code: "CNY", englishName: "Chinese Yuan", chineseName: "人民幣"),
        CurrencyOption(code: "KRW", englishName: "South Korean Won", chineseName: "韓元"),
        CurrencyOption(code: "SGD", englishName: "Singapore Dollar", chineseName: "新加坡幣"),
        CurrencyOption(code: "CHF", englishName: "Swiss Franc", chineseName: "瑞士法郎"),
        CurrencyOption(code: "NZD", englishName: "New Zealand Dollar", chineseName: "紐幣")
    ]

    private var matchingCurrencies: [CurrencyOption] {
        let query = currency.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }
        return currencyOptions.filter {
            $0.code.lowercased().contains(query) ||
            $0.englishName.lowercased().contains(query) ||
            $0.chineseName.contains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Foreign Currency")
                .font(.title2.weight(.bold))
            TextField("Currency code (e.g. EUR)", text: $currency)
                .textFieldStyle(.roundedBorder)
            if !matchingCurrencies.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(matchingCurrencies.prefix(8)) { option in
                        Button {
                            currency = option.code
                        } label: {
                            HStack {
                                Text(option.code)
                                    .font(.body.weight(.semibold))
                                    .frame(width: 52, alignment: .leading)
                                Text(appLanguage == AppLanguage.traditionalChinese.rawValue
                                     ? option.chineseName
                                     : option.englishName)
                                    .foregroundStyle(FinTrackTheme.textSecondary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    }
                }
                .padding(8)
                .background(FinTrackTheme.surfaceHover, in: RoundedRectangle(cornerRadius: 8))
            }
            TextField("Current balance", text: $balance)
                .textFieldStyle(.roundedBorder)
            TextField("Average cost rate of current balance (NTD per unit)", text: $averageRate)
                .textFieldStyle(.roundedBorder)
            Text("Enter the weighted-average cost rate of the remaining balance, not the total exchanged amount. For example, USD 497.30 at NTD 31.5220 creates an NTD cost basis of about NTD 15,675.89.")
                .font(.caption)
                .foregroundStyle(FinTrackTheme.textSecondary)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func save() {
        let code = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count >= 3 && code.count <= 5,
              code != "NTD",
              let balanceValue = Double(balance), balanceValue >= 0,
              let rateValue = Double(averageRate), rateValue > 0 else {
            errorMessage = "Enter a valid currency code, balance, and average rate."
            return
        }

        do {
            try appModel.createAsset(
                name: code,
                assetGroup: "liquid_asset",
                category: "Foreign Currency",
                currency: code,
                value: balanceValue,
                ntdValue: balanceValue * rateValue
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ForeignCurrencySummary: Identifiable {
    let currency: String
    let amount: Double
    let ntdValue: Double
    let rate: Double?
    let assetIDs: [Int64]

    var id: String { currency }
}

struct OverviewView: View {
    let showChanges: Bool
    @EnvironmentObject private var appModel: AppModel
    @State private var showingAddAsset = false
    @State private var showingAddLiability = false
    @State private var editingAsset: DatabaseManager.AssetRecord?
    @State private var editingLiability: DatabaseManager.LiabilityRecord?

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                MetricCard(title: "Total Assets", value: ntd(appModel.assetTotals.total), change: percentageChange(appModel.assetTotals.total, previousValue(for: "totalAssets")) + " vs last month")
                MetricCard(title: "Total Liabilities", value: ntd(appModel.liabilityTotals.total), change: percentageChange(appModel.liabilityTotals.total, previousValue(for: "totalLiabilities")) + " vs last month")
                MetricCard(title: "Net Worth", value: ntd(appModel.assetTotals.total - appModel.liabilityTotals.total), change: percentageChange(appModel.assetTotals.total - appModel.liabilityTotals.total, previousValue(for: "netWorth")) + " vs last month")
            }
            .padding(.horizontal, 24)

            Rectangle()
                .fill(FinTrackTheme.divider)
                .frame(height: 1)
                .padding(.horizontal, 24)

            ScrollView {
                VStack(spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        DetailCard(title: "Total Assets Details", showChanges: showChanges, onAdd: {
                    showingAddAsset = true
                        }, sections: assetSections)

                        VStack(spacing: 16) {
                            DetailCard(title: "Total Liabilities Details", showChanges: showChanges, onAdd: {
                                showingAddLiability = true
                            }, sections: liabilitySections)
                            FinancialIndicatorsCard(
                                assetTotals: appModel.assetTotals,
                                liabilityTotals: appModel.liabilityTotals
                            )
                        }
                    }

                    NetWorthHistoryCard()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showingAddAsset) {
            AddAssetSheet()
        }
        .sheet(isPresented: $showingAddLiability) {
            AddLiabilitySheet()
        }
        .sheet(item: $editingAsset) { asset in
            EditAssetSheet(asset: asset)
        }
        .sheet(item: $editingLiability) { liability in
            EditLiabilitySheet(liability: liability)
        }
        .onAppear {
            appModel.refreshAssets()
            appModel.refreshLiabilities()
            Task { await appModel.refreshMarketData() }
        }
    }

    private var assetSections: [DetailSection] {
        [
            DetailSection(title: "Liquid Assets", value: ntd(appModel.assetTotals.liquidAsset), change: percentageChange(appModel.assetTotals.liquidAsset, previousValue(for: "assetGroup|liquid_asset")), children: children(for: "liquid_asset")),
            DetailSection(title: "Liquid Investments", value: ntd(appModel.assetTotals.liquidInvestment), change: percentageChange(appModel.assetTotals.liquidInvestment, previousValue(for: "assetGroup|liquid_investment")), children: children(for: "liquid_investment")),
            DetailSection(title: "Long-term Investment", value: ntd(appModel.assetTotals.longTermInvestment), change: percentageChange(appModel.assetTotals.longTermInvestment, previousValue(for: "assetGroup|long_term_investment")), children: children(for: "long_term_investment")),
            DetailSection(title: "Other Assets", value: ntd(appModel.assetTotals.otherAsset), change: percentageChange(appModel.assetTotals.otherAsset, previousValue(for: "assetGroup|other_asset")), children: children(for: "other_asset"))
        ]
    }

    private var liabilitySections: [DetailSection] {
        [
            DetailSection(title: "Short-term Liabilities", value: ntd(appModel.liabilityTotals.shortTerm), change: percentageChange(appModel.liabilityTotals.shortTerm, previousValue(for: "liabilityGroup|short_term")), children: liabilityChildren(for: "short_term")),
            DetailSection(title: "Long-term Liabilities", value: ntd(appModel.liabilityTotals.longTerm), change: percentageChange(appModel.liabilityTotals.longTerm, previousValue(for: "liabilityGroup|long_term")), children: liabilityChildren(for: "long_term")),
            DetailSection(title: "Total Liabilities", value: ntd(appModel.liabilityTotals.total), change: percentageChange(appModel.liabilityTotals.total, previousValue(for: "totalLiabilities")))
        ]
    }

    private func children(for group: String) -> [DetailRow] {
        let assetNames = appModel.assets
            .filter { $0.assetGroup == group }
            .map(\.name)
        let holdingCategories = appModel.assetCategoryTotals.keys.compactMap { key -> String? in
            guard key.hasPrefix("\(group)|") else { return nil }
            return String(key.dropFirst(group.count + 1))
        }
        let names = Set(assetNames + holdingCategories).sorted(by: >)

        return names.map { name in
                let asset = appModel.assets.first { $0.assetGroup == group && $0.name == name }
                return DetailRow(
                    name: name,
                    value: ntd(appModel.assetCategoryTotals["\(group)|\(name)"] ?? asset?.ntdValue ?? 0),
                    change: percentageChange(
                        appModel.assetCategoryTotals["\(group)|\(name)"] ?? asset?.ntdValue ?? 0,
                        previousValue(for: appModel.assetCategoryTotals["\(group)|\(name)"] != nil
                            ? "assetGroup|\(group)|\(name)"
                            : "asset|\(group)|\(name)")
                    ),
                    onDelete: asset.map { record in { appModel.deleteAsset(id: record.id) } },
                    onEdit: asset.map { record in { editingAsset = record } }
                )
            }
    }

    private func liabilityChildren(for group: String) -> [DetailRow] {
        appModel.liabilities
            .filter { $0.liabilityGroup == group }
            .map { liability in
                DetailRow(
                    name: liability.name,
                    value: liability.currency == "NTD"
                        ? ntd(liability.balance)
                        : "\(liability.currency) \(liability.balance)",
                    change: percentageChange(liability.balance, previousValue(for: "liability|\(group)|\(liability.name)")),
                    onDelete: { appModel.deleteLiability(id: liability.id) },
                    onEdit: { editingLiability = liability }
                )
            }
    }

    private var monthlyBaseline: DatabaseManager.Snapshot? {
        guard let latest = appModel.snapshots.last,
              let currentDate = snapshotDate(latest.date),
              let cutoff = Calendar.current.date(byAdding: .month, value: -1, to: currentDate) else { return nil }
        return appModel.snapshots.last { snapshot in
            guard let date = snapshotDate(snapshot.date) else { return false }
            return date <= cutoff
        }
    }

    private func previousValue(for key: String) -> Double? {
        if key == "totalAssets" { return monthlyBaseline?.totalAssets }
        if key == "totalLiabilities" { return monthlyBaseline?.totalLiabilities }
        if key == "netWorth" { return monthlyBaseline?.netWorth }
        return monthlyBaseline?.detailValues[key]
    }

    private func percentageChange(_ current: Double, _ previous: Double?) -> String {
        guard let previous, previous != 0 else { return "—" }
        let change = (current - previous) / abs(previous) * 100
        return String(format: "%+.1f%%", change)
    }

    private func snapshotDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}

private func ntd(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 0
    formatter.minimumFractionDigits = 0
    return "NTD \(formatter.string(from: NSNumber(value: value)) ?? "0")"
}

private func money(_ value: Double, currency: String) -> String {
    let prefix: String
    switch currency {
    case "USD": prefix = "$"
    case "JPY": prefix = "¥"
    case "NTD": prefix = "NTD "
    default: prefix = "\(currency) "
    }
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    let isNTD = currency == "NTD" || currency == "TWD"
    formatter.minimumFractionDigits = isNTD ? 0 : 2
    formatter.maximumFractionDigits = isNTD ? 0 : 2
    return "\(prefix)\(formatter.string(from: NSNumber(value: value)) ?? (isNTD ? "0" : "0.00"))"
}

private func lastPriceMoney(_ value: Double, currency: String) -> String {
    let prefix: String
    switch currency {
    case "USD": prefix = "$"
    case "JPY": prefix = "¥"
    case "NTD", "TWD": prefix = "NTD "
    default: prefix = "\(currency) "
    }
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    return "\(prefix)\(formatter.string(from: NSNumber(value: value)) ?? "0.00")"
}

private func shares(_ value: Double, market: String) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    let isTaiwan = market.caseInsensitiveCompare("Taiwan") == .orderedSame
        || market.caseInsensitiveCompare("TW") == .orderedSame
    formatter.minimumFractionDigits = isTaiwan ? 0 : 2
    formatter.maximumFractionDigits = isTaiwan ? 0 : 2
    return formatter.string(from: NSNumber(value: value)) ?? (isTaiwan ? "0" : "0.00")
}

private func marketCode(for symbol: String) -> String {
    let normalized = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard let suffix = normalized.split(separator: ".", maxSplits: 1).last,
          normalized.contains(".") else {
        return "US"
    }

    switch String(suffix) {
    case "TW": return "TW"
    case "T": return "JP"
    case "KS", "KQ": return "KR"
    case "HK": return "HK"
    case "SS", "SZ": return "CN"
    case "L": return "GB"
    case "AX": return "AU"
    case "TO": return "CA"
    case "SI": return "SG"
    case "SW": return "CH"
    case "PA": return "FR"
    case "DE": return "DE"
    default: return String(suffix)
    }
}

private func signedNTD(_ value: Double) -> String {
    return value < 0 ? "-\(ntd(abs(value)))" : ntd(value)
}

private func performanceColor(isNegative: Bool, mode: String) -> Color {
    switch mode {
    case "redUp": return isNegative ? FinTrackTheme.positive : FinTrackTheme.negative
    case "analog": return isNegative ? FinTrackTheme.warning : FinTrackTheme.info
    default: return isNegative ? FinTrackTheme.negative : FinTrackTheme.positive
    }
}

private let liabilityCategoryOptions = [
    "Loan",
    "Credit Card",
    "Mortgage",
    "Auto Loan",
    "Personal Loan",
    "Student Loan",
    "Tax Payable",
    "Other"
]

struct AddAssetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel
    @State private var name = ""
    @State private var assetGroup = "liquid_asset"
    @State private var currency = "NTD"
    @State private var amount = ""
    @State private var ntdCost = ""
    @State private var errorMessage: String?
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue

    private let assetGroups = [
        ("liquid_asset", "Liquid Asset"),
        ("liquid_investment", "Liquid Investment"),
        ("long_term_investment", "Long-term Investment"),
        ("other_asset", "Other Asset")
    ]
    private var currencies: [String] {
        Array(Set(["NTD", "USD", "JPY", currency])).sorted()
    }

    private var exchangeRate: String? {
        guard currency != "NTD",
              let foreignAmount = Double(amount),
              let cost = Double(ntdCost),
              foreignAmount > 0 else { return nil }
        return String(format: "%.4f", cost / foreignAmount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.text("Add Asset", language: appLanguage))
                .font(.title2.weight(.bold))

            TextField(L10n.text("Asset name", language: appLanguage), text: $name)
                .textFieldStyle(.roundedBorder)

            Picker(L10n.text("Asset group", language: appLanguage), selection: $assetGroup) {
                ForEach(assetGroups, id: \.0) { group in
                    Text(L10n.text(group.1, language: appLanguage)).tag(group.0)
                }
            }
            .pickerStyle(.menu)

            Picker(L10n.text("Currency", language: appLanguage), selection: $currency) {
                ForEach(currencies, id: \.self) { currency in
                    Text(currency).tag(currency)
                }
            }
            .pickerStyle(.menu)

            TextField(L10n.text(currency == "NTD" ? "Amount (NTD)" : "Original amount", language: appLanguage), text: $amount)
                .textFieldStyle(.roundedBorder)

            if currency != "NTD" {
                TextField(L10n.text("Current balance cost basis (NTD)", language: appLanguage), text: $ntdCost)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Text(L10n.text("Average exchange rate", language: appLanguage))
                    Spacer()
                    Text(exchangeRate.map { "NTD \($0)" } ?? "—")
                        .foregroundStyle(FinTrackTheme.textSecondary)
                }
                .font(.callout)
                Text(L10n.text("Only exchange or opening-fund cost is included. Dividends and investment gains are recorded separately.", language: appLanguage))
                    .font(.caption)
                    .foregroundStyle(FinTrackTheme.textSecondary)
            }

            HStack {
                Spacer()
                Button(L10n.text("Cancel", language: appLanguage)) { dismiss() }
                Button(L10n.text("Save", language: appLanguage)) {
                    saveAsset()
                }
                .buttonStyle(.borderedProminent)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func saveAsset() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let originalValue = Double(amount),
              originalValue >= 0 else {
            errorMessage = "Enter an asset name and a valid amount."
            return
        }

        let ntdValue: Double
        if currency == "NTD" {
            ntdValue = originalValue
        } else if originalValue == 0 && ntdCost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Empty category assets can be created with zero value.
            ntdValue = 0
        } else {
            guard let initialCost = Double(ntdCost), initialCost >= 0 else {
                errorMessage = "Enter the initial NTD cost for a foreign-currency asset."
                return
            }
            ntdValue = initialCost
        }

        do {
            try appModel.createAsset(
                name: name,
                assetGroup: assetGroup,
                category: name,
                currency: currency,
                value: originalValue,
                ntdValue: ntdValue
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AddLiabilitySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel
    @State private var name = ""
    @State private var group = "Short-term Liability"
    @State private var category = "Credit Card"
    @State private var currency = "NTD"
    @State private var balance = ""
    @State private var interestRate = ""
    @State private var errorMessage: String?
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue

    private let groups = ["Short-term Liability", "Long-term Liability"]
    private let currencies = ["NTD", "USD", "JPY"]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.text("Add Liability", language: appLanguage))
                .font(.title2.weight(.bold))

            TextField(L10n.text("Liability name", language: appLanguage), text: $name)
                .textFieldStyle(.roundedBorder)

            Picker(L10n.text("Group", language: appLanguage), selection: $group) {
                ForEach(groups, id: \.self) { group in
                    Text(L10n.text(group, language: appLanguage)).tag(group)
                }
            }
            .pickerStyle(.menu)

            Picker(L10n.text("Category", language: appLanguage), selection: $category) {
                ForEach(liabilityCategoryOptions, id: \.self) { option in
                    Text(L10n.text(option, language: appLanguage)).tag(option)
                }
            }
            .pickerStyle(.menu)

            Picker(L10n.text("Currency", language: appLanguage), selection: $currency) {
                ForEach(currencies, id: \.self) { currency in
                    Text(currency).tag(currency)
                }
            }
            .pickerStyle(.menu)

            TextField(L10n.text("Balance", language: appLanguage), text: $balance)
                .textFieldStyle(.roundedBorder)

            TextField(L10n.text("Interest rate (optional)", language: appLanguage), text: $interestRate)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button(L10n.text("Cancel", language: appLanguage)) { dismiss() }
                Button(L10n.text("Save", language: appLanguage)) {
                    saveLiability()
                }
                .buttonStyle(.borderedProminent)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func saveLiability() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let balanceValue = Double(balance),
              balanceValue >= 0 else {
            errorMessage = "Enter a liability name and a valid balance."
            return
        }

        let parsedInterestRate = interestRate.isEmpty ? nil : Double(interestRate)
        guard interestRate.isEmpty || parsedInterestRate != nil else {
            errorMessage = "Enter a valid interest rate."
            return
        }

        do {
            try appModel.createLiability(
                name: name,
                liabilityGroup: group == "Short-term Liability" ? "short_term" : "long_term",
                category: category,
                currency: currency,
                balance: balanceValue,
                interestRate: parsedInterestRate
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct EditAssetSheet: View {
    let asset: DatabaseManager.AssetRecord
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel
    @State private var name: String
    @State private var currency: String
    @State private var amount: String
    @State private var ntdCost: String
    @State private var errorMessage: String?

    private var currencies: [String] {
        Array(Set(["NTD", "USD", "JPY", currency])).sorted()
    }

    init(asset: DatabaseManager.AssetRecord) {
        self.asset = asset
        _name = State(initialValue: asset.name)
        _currency = State(initialValue: asset.currency)
        _amount = State(initialValue: String(asset.value))
        _ntdCost = State(initialValue: String(asset.ntdValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Edit Asset").font(.title2.weight(.bold))
            TextField("Asset name", text: $name).textFieldStyle(.roundedBorder)
            Picker("Currency", selection: $currency) {
                ForEach(currencies, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            TextField("Amount", text: $amount).textFieldStyle(.roundedBorder)
            if currency != "NTD" {
                TextField("Current balance cost basis (NTD)", text: $ntdCost).textFieldStyle(.roundedBorder)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }.buttonStyle(.borderedProminent)
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let value = Double(amount), value >= 0 else {
            errorMessage = "Enter a valid name and amount."
            return
        }
        let ntdValue: Double
        if currency == "NTD" {
            ntdValue = value
        } else if let cost = Double(ntdCost), cost >= 0 {
            ntdValue = cost
        } else {
            errorMessage = "Enter a valid initial NTD cost."
            return
        }
        do {
            try appModel.updateAsset(
                id: asset.id,
                name: name,
                assetGroup: asset.assetGroup,
                category: name,
                currency: currency,
                value: value,
                ntdValue: ntdValue
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct EditLiabilitySheet: View {
    let liability: DatabaseManager.LiabilityRecord
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel
    @State private var name: String
    @State private var group: String
    @State private var category: String
    @State private var currency: String
    @State private var balance: String
    @State private var interestRate: String
    @State private var errorMessage: String?
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue

    private let groups = ["Short-term Liability", "Long-term Liability"]
    private let currencies = ["NTD", "USD", "JPY"]

    init(liability: DatabaseManager.LiabilityRecord) {
        self.liability = liability
        _name = State(initialValue: liability.name)
        _group = State(initialValue: liability.liabilityGroup == "short_term" ? "Short-term Liability" : "Long-term Liability")
        _category = State(initialValue: liabilityCategoryOptions.contains(liability.category) ? liability.category : "Other")
        _currency = State(initialValue: liability.currency)
        _balance = State(initialValue: String(liability.balance))
        _interestRate = State(initialValue: liability.interestRate.map { String($0) } ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Edit Liability").font(.title2.weight(.bold))
            TextField("Liability name", text: $name).textFieldStyle(.roundedBorder)
            Picker("Group", selection: $group) {
                ForEach(groups, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            Picker(L10n.text("Category", language: appLanguage), selection: $category) {
                ForEach(liabilityCategoryOptions, id: \.self) { option in
                    Text(L10n.text(option, language: appLanguage)).tag(option)
                }
            }
            .pickerStyle(.menu)
            Picker("Currency", selection: $currency) {
                ForEach(currencies, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            TextField("Balance", text: $balance).textFieldStyle(.roundedBorder)
            TextField("Interest rate (optional)", text: $interestRate).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }.buttonStyle(.borderedProminent)
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let balanceValue = Double(balance), balanceValue >= 0 else {
            errorMessage = "Enter a valid name and balance."
            return
        }
        let parsedInterest = interestRate.isEmpty ? nil : Double(interestRate)
        guard interestRate.isEmpty || parsedInterest != nil else {
            errorMessage = "Enter a valid interest rate."
            return
        }
        do {
            try appModel.updateLiability(
                id: liability.id,
                name: name,
                liabilityGroup: group == "Short-term Liability" ? "short_term" : "long_term",
                category: category,
                currency: currency,
                balance: balanceValue,
                interestRate: parsedInterest
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AddHoldingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel
    @State private var subcategory = ""
    @State private var symbol = ""
    @State private var securityName = ""
    @State private var assetGroup = "liquid_investment"
    @State private var instrumentType = "stock"
    @State private var etfType = "equity"
    @State private var currency = "NTD"
    @State private var shares = ""
    @State private var totalCost = ""
    @State private var isRecurringHolding = false
    @State private var symbolSuggestions: [MarketDataClient.SearchResult] = []
    @State private var errorMessage: String?

    private let groups = [
        ("liquid_investment", "Liquid Investment"),
        ("long_term_investment", "Long-term Investment")
    ]

    private var availableSubcategories: [String] {
        Array(Set(appModel.holdingRecords
            .filter { $0.assetGroup == assetGroup }
            .map(\.category)))
            .sorted(by: >)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Holding").font(.title2.weight(.bold))
            VStack(alignment: .leading, spacing: 4) {
                TextField("Symbol", text: $symbol).textFieldStyle(.roundedBorder)
                if !symbolSuggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(symbolSuggestions) { suggestion in
                            Button {
                                symbol = suggestion.symbol
                                securityName = suggestion.displayName
                                symbolSuggestions = []
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.symbol)
                                    Text(suggestion.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            Picker("Asset group", selection: $assetGroup) {
                ForEach(groups, id: \.0) { group in
                    Text(group.1).tag(group.0)
                }
            }
            .pickerStyle(.menu)
            Picker("Subcategory", selection: $subcategory) {
                if availableSubcategories.isEmpty {
                    Text("No subcategories available").tag("")
                } else {
                    ForEach(availableSubcategories, id: \.self) { category in
                        Text(category).tag(category)
                    }
                }
            }
            .pickerStyle(.menu)

            Picker("Type", selection: $instrumentType) {
                Text("Stock").tag("stock")
                Text("ETF").tag("etf")
            }
            .pickerStyle(.segmented)
            if instrumentType == "etf" {
                Picker("ETF type", selection: $etfType) {
                    Text("Equity ETF").tag("equity")
                    Text("Bond ETF").tag("bond")
                }
                .pickerStyle(.menu)
            }
            Picker("Currency", selection: $currency) {
                Text("NTD").tag("NTD")
                Text("USD").tag("USD")
            }
            .pickerStyle(.menu)
            Toggle("This holding will be used for recurring investment", isOn: $isRecurringHolding)
            TextField("Shares", text: $shares).textFieldStyle(.roundedBorder)
            TextField("Total cost (\(currency))", text: $totalCost).textFieldStyle(.roundedBorder)
            Text("Holding cost and P&L stay in the original currency until an exchange transaction is recorded.")
                .font(.caption)
                .foregroundStyle(FinTrackTheme.textSecondary)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }.buttonStyle(.borderedProminent)
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear {
            if subcategory.isEmpty {
                subcategory = availableSubcategories.first ?? ""
            }
        }
        .onChange(of: assetGroup) { _, _ in
            subcategory = availableSubcategories.first ?? ""
        }
        .onChange(of: symbol) { _, newValue in
            Task {
                let query = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else {
                    symbolSuggestions = []
                    return
                }
                symbolSuggestions = await appModel.searchMarketSymbols(query: query)
            }
        }
    }

    private func save() {
        let sharesText = shares.isEmpty && isRecurringHolding ? "0" : shares
        let costText = totalCost.isEmpty && isRecurringHolding ? "0" : totalCost
        guard !symbol.isEmpty, !securityName.isEmpty,
              !subcategory.isEmpty, let shareValue = Double(sharesText),
              let cost = Double(costText), shareValue >= 0, cost >= 0,
              isRecurringHolding || (shareValue > 0 && cost > 0) else {
            errorMessage = "Complete the holding fields with valid values."
            return
        }
        do {
            try appModel.createHolding(
                assetName: securityName,
                assetGroup: assetGroup,
                category: subcategory,
                symbol: symbol,
                securityName: securityName,
                market: marketCode(for: symbol),
                instrumentType: instrumentType,
                etfType: instrumentType == "etf" ? etfType : nil,
                currency: currency,
                shares: shareValue,
                totalCost: cost,
                isRecurringHolding: isRecurringHolding
            )
            dismiss()
            Task { await appModel.refreshMarketData() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct EditHoldingSheet: View {
    let holding: DatabaseManager.HoldingRecord
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel
    @State private var symbol: String
    @State private var securityName: String
    @State private var instrumentType: String
    @State private var etfType: String
    @State private var currency: String
    @State private var shares: String
    @State private var totalCost: String
    @State private var suggestions: [MarketDataClient.SearchResult] = []
    @State private var errorMessage: String?

    init(holding: DatabaseManager.HoldingRecord) {
        self.holding = holding
        _symbol = State(initialValue: holding.symbol)
        _securityName = State(initialValue: holding.securityName)
        _instrumentType = State(initialValue: holding.instrumentType)
        _etfType = State(initialValue: holding.etfType ?? "equity")
        _currency = State(initialValue: holding.currency)
        _shares = State(initialValue: String(holding.shares))
        _totalCost = State(initialValue: String(holding.totalCost))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Holding").font(.title2.weight(.bold))
            TextField("Symbol", text: $symbol).textFieldStyle(.roundedBorder)
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(suggestions) { suggestion in
                        Button {
                            symbol = suggestion.symbol
                            securityName = suggestion.displayName
                            suggestions = []
                        } label: {
                            VStack(alignment: .leading) {
                                Text(suggestion.symbol)
                                Text(suggestion.displayName).font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            Picker("Type", selection: $instrumentType) {
                Text("Stock").tag("stock")
                Text("ETF").tag("etf")
            }
            .pickerStyle(.segmented)
            if instrumentType == "etf" {
                Picker("ETF type", selection: $etfType) {
                    Text("Equity ETF").tag("equity")
                    Text("Bond ETF").tag("bond")
                }
                .pickerStyle(.menu)
            }
            Picker("Currency", selection: $currency) {
                Text("NTD").tag("NTD")
                Text("USD").tag("USD")
            }
            .pickerStyle(.menu)
            TextField("Shares", text: $shares).textFieldStyle(.roundedBorder)
            TextField("Total cost (\(currency))", text: $totalCost).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }.buttonStyle(.borderedProminent)
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(24)
        .frame(width: 440)
        .onChange(of: symbol) { _, newValue in
            Task {
                let query = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else {
                    suggestions = []
                    return
                }
                suggestions = await appModel.searchMarketSymbols(query: query)
            }
        }
    }

    private func save() {
        guard !symbol.isEmpty, !securityName.isEmpty,
              let shareValue = Double(shares), shareValue >= 0,
              let cost = Double(totalCost), cost >= 0 else {
            errorMessage = "Enter valid holding values."
            return
        }
        do {
            try appModel.updateHolding(
                id: holding.id,
                symbol: symbol,
                securityName: securityName,
                market: marketCode(for: symbol),
                instrumentType: instrumentType,
                etfType: instrumentType == "etf" ? etfType : nil,
                currency: currency,
                shares: shareValue,
                totalCost: cost
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PortfolioView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var showingAddHolding = false
    @State private var editingHolding: DatabaseManager.HoldingRecord?
    @State private var pendingDeleteHolding: PortfolioHolding?
    @State private var dividendHolding: DatabaseManager.HoldingRecord?
    @State private var sortAscending = true
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    @AppStorage("performanceColorMode") private var performanceColorMode = "greenUp"

    var body: some View {
        let displayedHoldings = appModel.holdingRecords
            .sorted {
                let lhsKey = String($0.securityName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
                let rhsKey = String($1.securityName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
                if lhsKey != rhsKey { return sortAscending ? lhsKey < rhsKey : lhsKey > rhsKey }
                let comparison = $0.securityName.localizedCaseInsensitiveCompare($1.securityName)
                return sortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
            }
            .map(makePortfolioHolding)
        let portfolioTotals = appModel.portfolioTotals

        VStack(spacing: 16) {
            HStack(spacing: 16) {
                PortfolioMetricCard(
                    title: "TOTAL P&L",
                    value: portfolioTotals.pricedHoldings > 0 ? signedNTD(portfolioTotals.totalPLNTD) : "—",
                    detail: L10n.text(
                        portfolioTotals.pricedHoldings > 0 ? "NTD converted" : "No market prices",
                        language: appLanguage
                    ),
                    tint: performanceColor(isNegative: portfolioTotals.totalPLNTD < 0, mode: performanceColorMode),
                    height: 100
                )
                PortfolioMetricCard(
                    title: "TODAY",
                    value: appModel.todayPLNTD.map(signedNTD) ?? (appModel.isRefreshingMarketData ? "…" : "—"),
                    detail: appModel.isRefreshingMarketData
                        ? L10n.text("Updating market prices", language: appLanguage)
                        : (appModel.todayPLNTD == nil
                            ? L10n.text("No market prices", language: appLanguage)
                            : L10n.text("vs previous close", language: appLanguage)),
                    tint: appModel.todayPLNTD.map { performanceColor(isNegative: $0 < 0, mode: performanceColorMode) } ?? .primary,
                    height: 100
                )
                PortfolioMetricCard(
                    title: "MARKET VALUE",
                    value: portfolioTotals.pricedHoldings > 0 ? ntd(portfolioTotals.marketValueNTD) : "—",
                    detail: "\(displayedHoldings.count) \(L10n.text("holdings", language: appLanguage))",
                    tint: .primary,
                    height: 100
                )
            }
            .padding(.horizontal, 24)

            Rectangle()
                .fill(FinTrackTheme.divider)
                .frame(height: 1)
                .padding(.horizontal, 24)

            ScrollView {
                VStack(spacing: 16) {
                    AllocationCard(records: appModel.allocationRecords)
                    PositionsCard(
                        holdings: displayedHoldings,
                        onAdd: { showingAddHolding = true },
                        onEdit: { id in editingHolding = appModel.holdingRecords.first { $0.id == id } },
                        onDelete: { id in pendingDeleteHolding = displayedHoldings.first { $0.id == id } },
                        onAddDividend: { id in dividendHolding = appModel.holdingRecords.first { $0.id == id } },
                        sortAscending: sortAscending,
                        onToggleSort: { sortAscending.toggle() }
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showingAddHolding) {
            AddHoldingSheet()
        }
        .sheet(item: $editingHolding) { holding in
            EditHoldingSheet(holding: holding)
        }
        .sheet(item: $dividendHolding) { holding in
            AddDividendSheet(holding: holding)
        }
        .alert(item: $pendingDeleteHolding) { holding in
            Alert(
                title: Text("Delete Holding?"),
                message: Text("This will remove \(holding.securityName) from your portfolio."),
                primaryButton: .destructive(Text("Delete")) {
                    appModel.deleteHolding(id: holding.id)
                },
                secondaryButton: .cancel()
            )
        }
        .onAppear {
            appModel.refreshHoldings()
            Task { await appModel.refreshMarketData() }
        }
    }

    private func makePortfolioHolding(_ holding: DatabaseManager.HoldingRecord) -> PortfolioHolding {
        let average = holding.shares > 0
            ? money(holding.totalCost / holding.shares, currency: holding.currency)
            : "—"
        let price = holding.marketPrice.map { lastPriceMoney($0, currency: holding.currency) } ?? "—"
        let value = holding.marketValue.map { holdingValueMoney($0, currency: holding.currency, market: holding.market) } ?? "—"
        let profitLoss = holding.capitalGainLoss.map { money($0, currency: holding.currency) } ?? "—"
        let returnRate: String
        if let gain = holding.capitalGainLoss, holding.totalCost > 0 {
            returnRate = String(format: "%.2f%%", gain / holding.totalCost * 100)
        } else {
            returnRate = "—"
        }
        return PortfolioHolding(
            id: holding.id,
            symbol: holding.symbol,
            securityName: holding.securityName,
            quantity: shares(holding.shares, market: holding.market),
            average: average,
            price: price,
            capitalPL: profitLoss,
            totalPL: profitLoss,
            capitalRate: "—",
            totalRate: returnRate,
            value: value,
            cost: money(holding.totalCost, currency: holding.currency),
            weight: "—",
            totalReturn: "",
            fx: ""
        )
    }
}

private func holdingValueMoney(_ value: Double, currency: String, market: String) -> String {
    let isTaiwan = market.caseInsensitiveCompare("Taiwan") == .orderedSame
        || market.caseInsensitiveCompare("TW") == .orderedSame
    guard isTaiwan else { return money(value, currency: currency) }
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 0
    let prefix = currency == "NTD" ? "NTD " : "\(currency) "
    return "\(prefix)\(formatter.string(from: NSNumber(value: value)) ?? "0")"
}

struct PortfolioMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color
    let height: CGFloat
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue

    init(title: String, value: String, detail: String, tint: Color, height: CGFloat = 100) {
        self.title = title
        self.value = value
        self.detail = detail
        self.tint = tint
        self.height = height
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text(title, language: appLanguage)).font(.caption.weight(.bold)).foregroundStyle(FinTrackTheme.textSecondary)
            Text(value).font(.title2.weight(.bold)).foregroundStyle(tint)
            Text(L10n.text(detail, language: appLanguage)).font(.caption).foregroundStyle(tint == .primary ? .secondary : tint)
        }
        .padding(14)
        .frame(height: height, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(FinTrackTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(FinTrackTheme.border))
    }
}

struct PositionsCard: View {
    let holdings: [PortfolioHolding]
    let onAdd: () -> Void
    let onEdit: (Int64) -> Void
    let onDelete: (Int64) -> Void
    let onAddDividend: (Int64) -> Void
    let sortAscending: Bool
    let onToggleSort: () -> Void
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    @AppStorage("performanceColorMode") private var performanceColorMode = "greenUp"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.text("HOLDINGS", language: appLanguage)).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                Spacer()
                Button(action: onAdd) {
                    Image(systemName: "plus")
                }
                    .buttonStyle(.plain)
                    .font(.callout.weight(.semibold))
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            HStack(spacing: 12) {
                Button(action: onToggleSort) {
                    HStack(spacing: 6) {
                        Text(L10n.text("SYMBOL", language: appLanguage))
                        Image(systemName: sortAscending ? "arrow.down" : "arrow.up")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                Text(L10n.text("LAST", language: appLanguage))
                    .frame(width: 96, alignment: .trailing)
                Text(L10n.text("VALUE", language: appLanguage))
                    .frame(width: 112, alignment: .trailing)
                Text(L10n.text("P&L", language: appLanguage))
                    .frame(width: 132, alignment: .trailing)
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    if holdings.isEmpty {
                        Text(L10n.text("No holdings yet. Click Add to create one.", language: appLanguage))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 160)
                    } else {
                        ForEach(holdings) { holding in
                            positionRow(holding)
                        }
                    }
                }
            }
            .frame(maxHeight: 480)
        }
        .background(FinTrackTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(FinTrackTheme.border))
    }

    private func positionRow(_ holding: PortfolioHolding) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                CompanyLogoView(symbol: holding.symbol, name: holding.securityName)
                VStack(alignment: .leading, spacing: 3) {
                    Text(holding.securityName)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    HStack(spacing: 4) {
                        Text("\(holding.quantity) \(L10n.text("shares", language: appLanguage))")
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text("·")
                        Text(holding.symbol)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(holding.price).font(.headline)
                .frame(width: 96, alignment: .trailing)
            Text(holding.value).font(.headline)
                .frame(width: 112, alignment: .trailing)
            VStack(alignment: .trailing, spacing: 3) {
                Text(holding.totalPL).font(.headline).foregroundStyle(performanceColor(isNegative: holding.isNegative, mode: performanceColorMode))
                Text(holding.totalRate).font(.caption).foregroundStyle(performanceColor(isNegative: holding.isNegative, mode: performanceColorMode))
            }
            .frame(width: 132, alignment: .trailing)
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.secondary.opacity(0.15)).frame(height: 1) }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Edit") { onEdit(holding.id) }
            Button("Add Dividend") { onAddDividend(holding.id) }
            Divider()
            Button("Delete", role: .destructive) { onDelete(holding.id) }
        }
    }
}

struct DividendManagementView: View {
    @EnvironmentObject private var appModel: AppModel
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    @State private var showingAdd = false
    @State private var editing: DatabaseManager.DividendRecord?
    @State private var pendingDelete: DatabaseManager.DividendRecord?

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: { showingAdd = true }) { Image(systemName: "plus") }
                        .buttonStyle(.plain)
                        .font(.callout.weight(.semibold))
                }
                .padding(.horizontal, 48)
                .padding(.top, 16)
                .padding(.bottom, 10)

                HStack {
                    Text(L10n.text("SECURITY", language: appLanguage)).frame(maxWidth: .infinity, alignment: .leading)
                    Text(L10n.text("DATE", language: appLanguage)).frame(width: 130, alignment: .trailing)
                    Text(L10n.text("AMOUNT", language: appLanguage)).frame(width: 140, alignment: .trailing)
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 48)
                .padding(.top, 8)
                .padding(.bottom, 10)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        if appModel.dividendRecords.isEmpty {
                            Text("No dividends recorded. Click + to add one.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 180)
                        } else {
                            ForEach(appModel.dividendRecords) { dividend in
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(dividend.securityName)
                                            .font(.headline)
                                            .lineLimit(1)
                                        Text(dividend.symbol).font(.caption).foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(dividend.payDate)
                                        .frame(width: 130, alignment: .trailing)
                                        .padding(.top, 2)
                                    Text(money(dividend.amount, currency: dividend.currency))
                                        .frame(width: 140, alignment: .trailing)
                                        .padding(.top, 2)
                                }
                                .padding(.horizontal, 48)
                                .padding(.vertical, 11)
                                .contentShape(Rectangle())
                                .contextMenu {
                                    Button("Edit") { editing = dividend }
                                    Divider()
                                    Button("Delete", role: .destructive) { pendingDelete = dividend }
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 520)
            }
            .background(FinTrackTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(FinTrackTheme.border))
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .sheet(isPresented: $showingAdd) { AddDividendManagementSheet() }
        .sheet(item: $editing) { dividend in EditDividendSheet(dividend: dividend) }
        .alert(item: $pendingDelete) { dividend in
            Alert(
                title: Text("Delete Dividend?"),
                message: Text("This dividend record will be removed."),
                primaryButton: .destructive(Text("Delete")) { appModel.deleteDividend(id: dividend.id) },
                secondaryButton: .cancel()
            )
        }
    }
}

struct AddDividendManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel
    @State private var holdingID: Int64?
    @State private var payDate = Date()
    @State private var amount = ""
    @State private var currency = "NTD"
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Dividend").font(.title2.weight(.bold))
            Picker("Security", selection: $holdingID) {
                Text("Select a holding").tag(nil as Int64?)
                ForEach(appModel.holdingRecords) { holding in
                    Text("\(holding.securityName) (\(holding.symbol))").tag(holding.id as Int64?)
                }
            }
            .pickerStyle(.menu)
            DatePicker("Payment date", selection: $payDate, displayedComponents: .date)
            TextField("Amount", text: $amount).textFieldStyle(.roundedBorder)
            Picker("Currency", selection: $currency) {
                Text("NTD").tag("NTD")
                Text("USD").tag("USD")
                Text("JPY").tag("JPY")
            }
            .pickerStyle(.menu)
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Save") { save() }.buttonStyle(.borderedProminent) }
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func save() {
        guard let holdingID, let value = Double(amount), value > 0 else {
            errorMessage = "Select a security and enter an amount greater than zero."
            return
        }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withFullDate]
        do {
            try appModel.addDividend(holdingID: holdingID, payDate: formatter.string(from: payDate), amount: value, currency: currency)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

struct EditDividendSheet: View {
    let dividend: DatabaseManager.DividendRecord
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel
    @State private var payDate: Date
    @State private var amount: String
    @State private var currency: String
    @State private var errorMessage: String?

    init(dividend: DatabaseManager.DividendRecord) {
        self.dividend = dividend
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withFullDate]
        _payDate = State(initialValue: formatter.date(from: dividend.payDate) ?? Date())
        _amount = State(initialValue: String(dividend.amount))
        _currency = State(initialValue: dividend.currency)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Dividend").font(.title2.weight(.bold))
            Text(dividend.securityName).foregroundStyle(.secondary)
            DatePicker("Payment date", selection: $payDate, displayedComponents: .date)
            TextField("Amount", text: $amount).textFieldStyle(.roundedBorder)
            Picker("Currency", selection: $currency) {
                Text("NTD").tag("NTD"); Text("USD").tag("USD"); Text("JPY").tag("JPY")
            }.pickerStyle(.menu)
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Save") { save() }.buttonStyle(.borderedProminent) }
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func save() {
        guard let value = Double(amount), value > 0 else { errorMessage = "Enter an amount greater than zero."; return }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withFullDate]
        do {
            try appModel.updateDividend(id: dividend.id, payDate: formatter.string(from: payDate), amount: value, currency: currency)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

struct AddDividendSheet: View {
    let holding: DatabaseManager.HoldingRecord
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel
    @State private var payDate = Date()
    @State private var amount = ""
    @State private var currency: String
    @State private var errorMessage: String?

    init(holding: DatabaseManager.HoldingRecord) {
        self.holding = holding
        _currency = State(initialValue: holding.currency)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Dividend").font(.title2.weight(.bold))
            Text(holding.securityName).foregroundStyle(.secondary)
            DatePicker("Payment date", selection: $payDate, displayedComponents: .date)
            TextField("Amount", text: $amount).textFieldStyle(.roundedBorder)
            Picker("Currency", selection: $currency) {
                Text("NTD").tag("NTD")
                Text("USD").tag("USD")
                Text("JPY").tag("JPY")
            }
            .pickerStyle(.menu)
            Text("Dividends are recorded separately and are not included in exchange-rate cost calculations.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }.buttonStyle(.borderedProminent)
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func save() {
        guard let value = Double(amount), value > 0 else {
            errorMessage = "Enter a dividend amount greater than zero."
            return
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        do {
            try appModel.addDividend(
                holdingID: holding.id,
                payDate: formatter.string(from: payDate),
                amount: value,
                currency: currency
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AllocationCard: View {
    let records: [DatabaseManager.AllocationRecord]
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    @State private var hoveredIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("ALLOCATION", language: appLanguage))
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            if records.isEmpty {
                Text(L10n.text("Allocation will appear after holdings and market prices are available.", language: appLanguage))
                    .foregroundStyle(.secondary)
            } else {
                let total = rankedRecords.reduce(0) { $0 + $1.valueNTD }
                HStack(alignment: .center, spacing: 0) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.08), lineWidth: 38)
                        ForEach(Array(rankedRecords.enumerated()), id: \.element.id) { index, record in
                            Circle()
                                .trim(
                                    from: allocationStart(for: index, total: total),
                                    to: allocationStart(for: index, total: total) + allocationFraction(record, total: total)
                                )
                                .stroke(
                                    allocationColor(index),
                                    style: StrokeStyle(lineWidth: hoveredIndex == index ? 44 : 38, lineCap: .butt)
                                )
                                .rotationEffect(.degrees(-90))
                                .scaleEffect(hoveredIndex == index ? 1.04 : 1)
                        }
                    }
                    .frame(width: 120, height: 120)
                    .overlay {
                        GeometryReader { geometry in
                            Color.clear
                                .contentShape(Circle())
                                .onContinuousHover(coordinateSpace: .local) { phase in
                                    switch phase {
                                    case .active(let location):
                                        hoveredIndex = allocationIndex(
                                            at: location,
                                            size: geometry.size,
                                            total: total
                                        )
                                    case .ended:
                                        hoveredIndex = nil
                                    }
                                }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(rankedRecords.enumerated()), id: \.element.id) { index, record in
                            HStack(spacing: 8) {
                                Circle().fill(allocationColor(index)).frame(width: 10, height: 10)
                                Text(record.name)
                                    .font(hoveredIndex == index ? .body.weight(.semibold) : .body)
                                    .foregroundStyle(hoveredIndex == index ? .primary : .secondary)
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 2)
                            .padding(.horizontal, 6)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .trailing, spacing: 10) {
                        ForEach(Array(rankedRecords.enumerated()), id: \.element.id) { index, record in
                            Text(total > 0 ? String(format: "%.1f%%", record.valueNTD / total * 100) : "0.0%")
                                .font(hoveredIndex == index ? .body.weight(.semibold) : .body)
                                .foregroundStyle(hoveredIndex == index ? .primary : .secondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .padding(.vertical, 2)
                                .padding(.horizontal, 6)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(FinTrackTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(FinTrackTheme.border))
    }

    private func allocationFraction(_ record: DatabaseManager.AllocationRecord, total: Double) -> CGFloat {
        total > 0 ? CGFloat(record.valueNTD / total) : 0
    }

    private var rankedRecords: [DatabaseManager.AllocationRecord] {
        records.sorted {
            if $0.valueNTD != $1.valueNTD {
                return $0.valueNTD > $1.valueNTD
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func allocationStart(for index: Int, total: Double) -> CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(rankedRecords.prefix(index).reduce(0) { $0 + $1.valueNTD } / total)
    }

    private func allocationIndex(at location: CGPoint, size: CGSize, total: Double) -> Int? {
        guard total > 0 else { return nil }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dx = location.x - center.x
        let dy = location.y - center.y
        let radius = min(size.width, size.height) / 2
        let distance = sqrt(dx * dx + dy * dy)
        let innerRadius = radius - 22
        guard distance <= radius && distance >= innerRadius else { return nil }

        var angle = atan2(Double(dy), Double(dx)) + Double.pi / 2
        if angle < 0 { angle += Double.pi * 2 }
        let position = CGFloat(angle / (Double.pi * 2))

        for index in rankedRecords.indices {
            let start = allocationStart(for: index, total: total)
            let end = start + allocationFraction(rankedRecords[index], total: total)
            if position >= start && position < end { return index }
        }
        return nil
    }

    private func allocationColor(_ index: Int) -> Color {
        let palette: [Color]
        if colorScheme == .light {
            palette = [
                Color(red: 0x6F / 255.0, green: 0x92 / 255.0, blue: 0x9F / 255.0),
                Color(red: 0x55 / 255.0, green: 0x76 / 255.0, blue: 0x83 / 255.0),
                Color(red: 0x66 / 255.0, green: 0x87 / 255.0, blue: 0x7E / 255.0),
                Color(red: 0x50 / 255.0, green: 0x6F / 255.0, blue: 0x69 / 255.0),
                Color(red: 0xB5 / 255.0, green: 0x8D / 255.0, blue: 0x49 / 255.0)
            ]
        } else {
            palette = [
                Color(red: 0x8B / 255.0, green: 0xA9 / 255.0, blue: 0xB5 / 255.0),
                Color(red: 0x6F / 255.0, green: 0x8D / 255.0, blue: 0x98 / 255.0),
                Color(red: 0x78 / 255.0, green: 0x96 / 255.0, blue: 0x8E / 255.0),
                Color(red: 0x65 / 255.0, green: 0x7D / 255.0, blue: 0x78 / 255.0),
                Color(red: 0xD0 / 255.0, green: 0xAC / 255.0, blue: 0x6C / 255.0)
            ]
        }
        return palette[index % palette.count]
    }
}

struct LegacyAllocationCard: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    private let segments = [
        AllocationSegment(name: "富邦公司治理", weight: "34.6%", value: 0.346, color: FinTrackTheme.allocationPalette[0]),
        AllocationSegment(name: "兆聯實業", weight: "19.4%", value: 0.194, color: FinTrackTheme.allocationPalette[1]),
        AllocationSegment(name: "VT", weight: "17.0%", value: 0.170, color: FinTrackTheme.allocationPalette[2]),
        AllocationSegment(name: "NVIDIA", weight: "13.6%", value: 0.136, color: FinTrackTheme.allocationPalette[3]),
        AllocationSegment(name: "BND", weight: "4.9%", value: 0.049, color: FinTrackTheme.allocationPalette[4]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.text("ALLOCATION", language: appLanguage)).font(.caption.weight(.bold)).foregroundStyle(.secondary)
            HStack(spacing: 28) {
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.12), lineWidth: 22)
                    ForEach(Array(segments.enumerated()), id: \.element.name) { index, segment in
                        Circle().trim(from: start(for: index), to: start(for: index) + segment.value)
                            .stroke(segment.color, style: StrokeStyle(lineWidth: 22, lineCap: .butt))
                            .rotationEffect(.degrees(-90))
                    }
                    VStack(spacing: 2) {
                        Text("10").font(.title.weight(.bold))
                        Text(L10n.text("ASSETS", language: appLanguage)).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 125, height: 125)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(segments) { segment in
                        HStack {
                            RoundedRectangle(cornerRadius: 3).fill(segment.color).frame(width: 16, height: 16)
                            Text(segment.name).font(.headline)
                            Spacer(minLength: 20)
                            Text(segment.weight).font(.headline).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            Divider()
            HStack(spacing: 6) {
                Circle().fill(.teal).frame(width: 10, height: 10)
                Text("ETFs 57%").foregroundStyle(.secondary)
                Spacer()
                Circle().fill(.orange).frame(width: 10, height: 10)
                Text("Stocks 43%").foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(16)
        .background(FinTrackTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(FinTrackTheme.border))
    }

    private func start(for index: Int) -> CGFloat {
        segments.prefix(index).reduce(0) { $0 + $1.value }
    }
}

struct AllocationSegment: Identifiable {
    let id = UUID()
    let name: String
    let weight: String
    let value: CGFloat
    let color: Color
}

struct PortfolioTable: View {
    let holdings: [PortfolioHolding]

    private let columns: [(String, CGFloat)] = [
        ("Ticker", 110), ("Qty", 82), ("Avg", 92), ("Price", 92),
        ("Cap P/L", 100), ("P/L", 100), ("Cap %", 84), ("Total %", 84),
        ("Value", 112), ("Cost", 112), ("Wt %", 78), ("Total P/L", 120), ("FX", 82)
    ]

    var body: some View {
        VStack(spacing: 0) {
            tableRow(values: columns.map { $0.0 }, isHeader: true)
            ForEach(holdings) { holding in
                tableRow(values: holding.values, isHeader: false)
            }
            tableRow(values: ["Total", "", "", "", "", "", "", "", "NT$1,596,724", "NT$667,537", "100.00%", "", ""], isHeader: true)
        }
        .background(FinTrackTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(FinTrackTheme.border))
    }

    private func tableRow(values: [String], isHeader: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                Text(values[index])
                    .font(isHeader ? .caption.weight(.bold) : .caption)
                    .foregroundStyle(isHeader ? .primary : .secondary)
                    .frame(width: column.1, alignment: index == 0 ? .leading : .trailing)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 9)
                    .background(isHeader ? Color.secondary.opacity(0.12) : Color.clear)
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.15))
                            .frame(width: 1)
                    }
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .frame(height: 1)
        }
    }
}

struct AllocationChart: View {
    var body: some View {
        chartPanel(title: "Allocation") {
            ZStack {
                Circle()
                    .stroke(FinTrackTheme.primary.opacity(0.8), style: StrokeStyle(lineWidth: 42, lineCap: .butt))
                Circle()
                    .trim(from: 0, to: 0.34)
                    .stroke(FinTrackTheme.info, style: StrokeStyle(lineWidth: 42, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                Text("100%")
                    .font(.headline)
            }
            .frame(width: 170, height: 170)
        }
    }
}

struct ReturnChart: View {
    private let bars: [(String, CGFloat)] = [("VT", 0.25), ("BND", 0.08), ("PLTR", 0.58), ("NVDA", 0.82), ("VFS", 0.04)]

    var body: some View {
        chartPanel(title: "Return %") {
            HStack(alignment: .bottom, spacing: 18) {
                ForEach(bars, id: \.0) { bar in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(bar.1 > 0.5 ? FinTrackTheme.positive : FinTrackTheme.primary)
                            .frame(width: 28, height: max(18, bar.1 * 150))
                        Text(bar.0).font(.caption2)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

private func chartPanel<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 12) {
        Text(title)
            .font(.title3.weight(.semibold))
        content()
            .frame(maxWidth: .infinity, minHeight: 190)
    }
    .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
    .padding(20)
    .background(FinTrackTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(FinTrackTheme.border))
}

struct PortfolioHolding: Identifiable {
    let id: Int64
    let symbol: String
    let securityName: String
    let quantity: String
    let average: String
    let price: String
    let capitalPL: String
    let totalPL: String
    let capitalRate: String
    let totalRate: String
    let value: String
    let cost: String
    let weight: String
    let totalReturn: String
    let fx: String

    var companyName: String {
        switch symbol {
        case "VT": return "Vanguard Total World"
        case "BND": return "Vanguard Total Bond"
        case "MONSTER": return "Monster Beverage"
        case "PALANTIR": return "Palantir Technologies"
        case "NVIDIA": return "NVIDIA Corporation"
        case "VINFAST": return "VinFast Auto"
        default: return symbol
        }
    }

    var isNegative: Bool { totalPL.contains("-") }

    var dayChange: String { isNegative ? "↘ -0.3" : "↗ +0.1" }

    var dayRate: String { isNegative ? "-0.6%" : "+0.2%" }

    var displayValue: String { convertToNTD(value) }

    var displayTotalPL: String { convertToNTD(totalPL) }

    var weightValue: CGFloat {
        (Double(weight.replacingOccurrences(of: "%", with: "")) ?? 0) / 100
    }

    private func convertToNTD(_ amount: String) -> String {
        guard amount.contains("$") && !amount.contains("NT$") else { return amount }
        let numericText = amount.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
        guard let numericValue = Double(numericText) else { return amount }
        return String(format: "NT$%,.2f", numericValue * 31.6858)
    }

    var values: [String] {
        [symbol, quantity, average, price, capitalPL, totalPL, capitalRate, totalRate, value, cost, weight, totalReturn, fx]
    }
}

struct FinancialIndicatorsCard: View {
    let assetTotals: DatabaseManager.AssetTotals
    let liabilityTotals: DatabaseManager.LiabilityTotals
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue

    private var indicators: [(String, String)] {
        let totalAssets = assetTotals.total
        let totalLiabilities = liabilityTotals.total
        let netWorth = totalAssets - totalLiabilities
        let liabilityRatio = totalAssets > 0 ? totalLiabilities / totalAssets * 100 : 0
        let cashRatio = totalLiabilities > 0 ? assetTotals.liquidAsset / totalLiabilities * 100 : 0
        let equityMultiplier = netWorth > 0 ? totalAssets / netWorth : 0

        return [
            ("Free Cash Flow", ntd(netWorth - assetTotals.otherAsset)),
            ("Liability Ratio", String(format: "%.2f%%", liabilityRatio)),
            ("Cash Ratio", String(format: "%.2f%%", cashRatio)),
            ("Equity Multiplier", String(format: "%.2f", equityMultiplier)),
            ("Net Worth Growth Rate", "0.00%")
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("Financial Indicators", language: appLanguage))
                .font(.title3.weight(.semibold))
            ForEach(indicators, id: \.0) { indicator in
                HStack {
                    Text(L10n.text(indicator.0, language: appLanguage))
                    Spacer()
                    Text(indicator.1).fontWeight(.semibold)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(FinTrackTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(FinTrackTheme.border))
    }
}

struct ChartPlaceholder: View {
    let title: String
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text(title, language: appLanguage))
                .font(.title3.weight(.semibold))
            Text(L10n.text("Chart area — to be connected to snapshots", language: appLanguage))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        .padding(20)
        .background(FinTrackTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(FinTrackTheme.border))
    }
}

struct NetWorthHistoryCard: View {
    @EnvironmentObject private var appModel: AppModel
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    @State private var didSaveSnapshot = false
    @State private var selectedDate: Date?
    @State private var historyRange: HistoryRange = .threeMonths

    private enum HistoryRange: String, CaseIterable {
        case oneMonth
        case threeMonths
        case sixMonths
        case oneYear
        case all
    }

    private var isChinese: Bool {
        appLanguage == AppLanguage.traditionalChinese.rawValue
    }

    private var allChartSnapshots: [(snapshot: DatabaseManager.Snapshot, date: Date)] {
        appModel.snapshots.compactMap { snapshot in
            guard let date = netWorthSnapshotDate(snapshot.date) else { return nil }
            return (snapshot, date)
        }
    }

    private var chartSnapshots: [(snapshot: DatabaseManager.Snapshot, date: Date)] {
        guard historyRange != .all, let latestDate = allChartSnapshots.last?.date else {
            return allChartSnapshots
        }
        let months: Int
        switch historyRange {
        case .oneMonth: months = 1
        case .threeMonths: months = 3
        case .sixMonths: months = 6
        case .oneYear: months = 12
        case .all: months = 0
        }
        let cutoff = Calendar.current.date(byAdding: .month, value: -months, to: latestDate) ?? latestDate
        let filtered = allChartSnapshots.filter { $0.date >= cutoff }
        // Keep the latest point visible even when the selected range has no data.
        return filtered.isEmpty ? Array(allChartSnapshots.suffix(1)) : filtered
    }

    private var historyRangeLabel: String {
        switch historyRange {
        case .oneMonth: return isChinese ? "1 個月" : "1M"
        case .threeMonths: return isChinese ? "3 個月" : "3M"
        case .sixMonths: return isChinese ? "6 個月" : "6M"
        case .oneYear: return isChinese ? "1 年" : "1Y"
        case .all: return isChinese ? "全部" : "All"
        }
    }

    private var selectedSnapshot: (snapshot: DatabaseManager.Snapshot, date: Date)? {
        guard let selectedDate, !chartSnapshots.isEmpty else { return nil }
        return chartSnapshots.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(L10n.text("Net Worth History", language: appLanguage))
                    .font(.title3.weight(.semibold))
                Spacer(minLength: 12)
                Menu {
                    ForEach(HistoryRange.allCases, id: \.self) { range in
                        Button {
                            historyRange = range
                            selectedDate = nil
                        } label: {
                            Text(historyRangeTitle(range))
                        }
                    }
                } label: {
                    Text(historyRangeLabel)
                        .foregroundStyle(FinTrackTheme.textSecondary)
                }
                .menuStyle(.borderlessButton)
                .help(isChinese ? "選擇圖表時間範圍" : "Choose chart time range")
                Button(action: createSnapshot) {
                    Label(
                        didSaveSnapshot ? (isChinese ? "已儲存" : "Saved") : (isChinese ? "建立快照" : "Snapshot"),
                        systemImage: didSaveSnapshot ? "checkmark.circle" : "plus.circle"
                    )
                }
                .buttonStyle(.borderless)
                .foregroundStyle(FinTrackTheme.primary)
                .accessibilityLabel(isChinese ? "建立淨值快照" : "Create net worth snapshot")
            }

            if appModel.snapshots.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 28))
                        .foregroundStyle(FinTrackTheme.primary)
                    Text(isChinese ? "尚無淨值歷史" : "No net worth history yet")
                        .font(.headline)
                    Text(isChinese ? "建立快照，開始追蹤淨值的變化。" : "Create a snapshot to start tracking your net worth over time.")
                        .font(.callout)
                        .foregroundStyle(FinTrackTheme.textSecondary)
                    Button(action: createSnapshot) {
                        Label(isChinese ? "建立第一筆快照" : "Create your first snapshot", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(FinTrackTheme.primary)
                }
                .frame(maxWidth: .infinity, minHeight: 190)
            } else {
                Chart(chartSnapshots, id: \.snapshot.id) { item in
                    if chartSnapshots.count >= 2 {
                    LineMark(
                        x: .value("Date", item.date),
                        y: .value("Net Worth", item.snapshot.netWorth)
                    )
                    .foregroundStyle(FinTrackTheme.primary)
                    .interpolationMethod(.catmullRom)
                    }

                    PointMark(
                        x: .value("Date", item.date),
                        y: .value("Net Worth", item.snapshot.netWorth)
                    )
                    .foregroundStyle(FinTrackTheme.primary)
                    .annotation(position: .top, spacing: 8) {
                        if chartSnapshots.count == 1 {
                            Text(snapshotDateText(item.date, includeYear: false))
                                .font(.caption)
                                .foregroundStyle(FinTrackTheme.textSecondary)
                        }
                    }
                }
                .chartXScale(domain: chartXDomain)
                .chartYScale(domain: chartYDomain)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(FinTrackTheme.divider)
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(compactNTD(amount, includeCurrency: false))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: chartXAxisDates) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(snapshotDateText(date, includeYear: chartSpansMultipleYears))
                                    .frame(width: 64, alignment: .center)
                                    .offset(x: -32)
                            }
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        if let plotFrameAnchor = proxy.plotFrame {
                            let plotFrame = geometry[plotFrameAnchor]
                            ZStack {
                            Color.clear
                                .contentShape(Rectangle())
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active(let location):
                                        let point = CGPoint(
                                            x: location.x - plotFrame.origin.x,
                                            y: location.y - plotFrame.origin.y
                                        )
                                        let nearest = chartSnapshots.compactMap { item -> (date: Date, distance: CGFloat)? in
                                            guard let x = proxy.position(forX: item.date),
                                                  let y = proxy.position(forY: item.snapshot.netWorth) else { return nil }
                                            let distance = hypot(point.x - x, point.y - y)
                                            return (item.date, distance)
                                        }.min { $0.distance < $1.distance }
                                        // Keep the hit target close to the visible point so
                                        // moving through the chart does not select a point.
                                        selectedDate = nearest.flatMap { $0.distance <= 10 ? $0.date : nil }
                                    case .ended:
                                        selectedDate = nil
                                    }
                                }

                            if let selectedSnapshot,
                               let pointX = proxy.position(forX: selectedSnapshot.date),
                               let pointY = proxy.position(forY: selectedSnapshot.snapshot.netWorth) {
                                NetWorthHoverCallout(
                                    value: ntd(selectedSnapshot.snapshot.netWorth),
                                    title: isChinese ? "淨值" : "Net Worth"
                                )
                                .position(
                                    x: min(max(plotFrame.minX + pointX, plotFrame.minX + 90), plotFrame.maxX - 90),
                                    y: min(pointY + plotFrame.minY + 52, plotFrame.maxY - 42)
                                )
                            }
                            }
                        }
                    }
                }
                .historyChartScrolling(isEnabled: true, initialDate: chartSnapshots.last?.date)
                .frame(height: 240)
                .id(appModel.snapshots.last?.id ?? "empty")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(FinTrackTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(FinTrackTheme.border))
        .onAppear {
            appModel.refreshSnapshots()
        }
        .alert(isChinese ? "建立快照失敗" : "Snapshot Failed", isPresented: Binding(
            get: { appModel.snapshotError != nil },
            set: { if !$0 { appModel.snapshotError = nil } }
        )) {
            Button(isChinese ? "好" : "OK") { appModel.snapshotError = nil }
        } message: {
            Text(appModel.snapshotError ?? (isChinese ? "無法儲存快照。" : "The snapshot could not be saved."))
        }
    }

    private var chartYDomain: ClosedRange<Double> {
        let values = chartSnapshots.map { $0.snapshot.netWorth }
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 0
        let dataSpan = maximum - minimum
        // Keep the observations near the visual centre. A zero baseline is not
        // useful here because it pushes a small history to the top of the plot.
        let padding = max(dataSpan * 0.35, max(abs(minimum), abs(maximum), 1) * 0.15)
        let lower = minimum - padding
        let upper = max(maximum + padding, lower + 1)
        return lower...upper
    }

    private var chartXDomain: ClosedRange<Date> {
        guard let first = chartSnapshots.first?.date,
              let last = chartSnapshots.last?.date else {
            let now = Date()
            return now.addingTimeInterval(-5 * 24 * 60 * 60)...now.addingTimeInterval(5 * 24 * 60 * 60)
        }
        let padding = max(2 * 24 * 60 * 60, min(5 * 24 * 60 * 60, last.timeIntervalSince(first) * 0.12))
        return first.addingTimeInterval(-padding)...last.addingTimeInterval(padding)
    }

    private var chartSpansMultipleYears: Bool {
        guard let first = chartSnapshots.first?.date, let last = chartSnapshots.last?.date else { return false }
        return Calendar.current.component(.year, from: first) != Calendar.current.component(.year, from: last)
    }

    private var chartXAxisDates: [Date] {
        let dates = chartSnapshots.map(\.date)
        guard dates.count > 10 else { return dates }
        // Keep labels tied to actual observations instead of automatic calendar
        // ticks, which can fall between points. For long ranges show a readable
        // subset while retaining both ends of the visible data.
        let step = max(1, Int(ceil(Double(dates.count - 1) / 8.0)))
        var selected = stride(from: 0, to: dates.count, by: step).map { dates[$0] }
        if selected.last != dates.last { selected.append(dates.last!) }
        return selected
    }

    private func createSnapshot() {
        guard appModel.saveManualSnapshot() else { return }
        withAnimation(.easeOut(duration: 0.15)) { didSaveSnapshot = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation(.easeOut(duration: 0.15)) { didSaveSnapshot = false }
        }
    }

    private func historyRangeTitle(_ range: HistoryRange) -> String {
        switch range {
        case .oneMonth: return isChinese ? "最近 1 個月" : "Last month"
        case .threeMonths: return isChinese ? "最近 3 個月" : "Last 3 months"
        case .sixMonths: return isChinese ? "最近 6 個月" : "Last 6 months"
        case .oneYear: return isChinese ? "最近 1 年" : "Last year"
        case .all: return isChinese ? "全部歷史" : "All history"
        }
    }
}

private struct NetWorthHoverCallout: View {
    let value: String
    let title: String

    var body: some View {
        VStack(spacing: -1) {
            Triangle()
                .fill(FinTrackTheme.cardBackground)
                .frame(width: 14, height: 7)
                .overlay {
                    Triangle()
                        .stroke(FinTrackTheme.border, lineWidth: 1)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(FinTrackTheme.textSecondary)
                Text(value)
                    .font(.callout.weight(.semibold))
            }
            .padding(8)
            .background(FinTrackTheme.cardBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(FinTrackTheme.border))
        }
        .fixedSize()
        .allowsHitTesting(false)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private extension View {
    @ViewBuilder
    func historyChartScrolling(isEnabled: Bool, initialDate: Date?) -> some View {
        if isEnabled, let initialDate {
            self
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: 10 * 24 * 60 * 60)
                .chartScrollPosition(initialX: initialDate)
        } else {
            self
        }
    }
}

private func netWorthSnapshotDate(_ value: String) -> Date? {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: value)
}

private func snapshotDateText(_ date: Date, includeYear: Bool) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.dateStyle = includeYear ? .medium : .medium
    formatter.timeStyle = .none
    if !includeYear { formatter.setLocalizedDateFormatFromTemplate("MMM d") }
    return formatter.string(from: date)
}

private func compactNTD(_ value: Double, includeCurrency: Bool = true) -> String {
    let absolute = abs(value)
    let suffix: String
    let scaled: Double
    if absolute >= 1_000_000_000 {
        scaled = value / 1_000_000_000
        suffix = "B"
    } else if absolute >= 1_000_000 {
        scaled = value / 1_000_000
        suffix = "M"
    } else if absolute >= 1_000 {
        scaled = value / 1_000
        suffix = "K"
    } else {
        scaled = value
        suffix = ""
    }
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = suffix.isEmpty ? 0 : 2
    formatter.minimumFractionDigits = 0
    let number = formatter.string(from: NSNumber(value: scaled)) ?? "0"
    return "\(includeCurrency ? "NTD " : "")\(number)\(suffix)"
}

struct IncomeStatementView: View {
    @EnvironmentObject private var appModel: AppModel
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    @State private var showingAdd = false
    @State private var addingSection = "income"
    @State private var addingParentID: Int64?
    @State private var editingItem: DatabaseManager.IncomeStatementItem?

    private let sections = [("income", "Income"), ("expense", "Expenses"), ("savings", "Savings")]

    private func children(of item: DatabaseManager.IncomeStatementItem) -> [DatabaseManager.IncomeStatementItem] {
        appModel.incomeStatementItems.filter { $0.parentID == item.id }
    }

    private func value(of item: DatabaseManager.IncomeStatementItem) -> Double {
        let childItems = children(of: item)
        return childItems.isEmpty ? item.amount : childItems.reduce(0) { $0 + value(of: $1) }
    }

    private func total(for section: String) -> Double {
        appModel.incomeStatementItems
            .filter { $0.section == section && $0.parentID == nil }
            .reduce(0) { $0 + value(of: $1) }
    }

    private var accountTotals: [(String, Double)] {
        let allocationItems = appModel.incomeStatementItems.filter {
            ($0.section == "expense" || $0.section == "savings") &&
            children(of: $0).isEmpty &&
            !($0.accountName?.isEmpty ?? true)
        }
        return Dictionary(grouping: allocationItems, by: { $0.accountName! })
            .map { account, items in (account, items.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.1 > $1.1 }
    }

    @ViewBuilder
    private func sectionCard(_ section: (String, String)) -> some View {
        IncomeStatementSectionCard(
            title: section.1,
            items: appModel.incomeStatementItems.filter { $0.section == section.0 },
            value: { value(of: $0) },
            onAdd: {
                addingSection = section.0
                addingParentID = nil
                showingAdd = true
            },
            onAddChild: { item in
                addingSection = section.0
                addingParentID = item.id
                showingAdd = true
            },
            onEdit: { editingItem = $0 },
            onDelete: { appModel.deleteIncomeStatementItem(id: $0.id) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            let monthlyProfit = total(for: "income") - total(for: "expense")
            HStack(spacing: 16) {
                MetricCard(title: "Total Income", value: ntd(total(for: "income")), change: "0.0% vs last month")
                MetricCard(title: "Total Expenses", value: ntd(total(for: "expense")), change: "0.0% vs last month")
                MetricCard(title: "Monthly Profit", value: ntd(monthlyProfit), change: "0.0% vs last month", warning: monthlyProfit < 0)
            }
            .padding(.horizontal, 24)

            Rectangle()
                .fill(FinTrackTheme.divider)
                .frame(height: 1)
                .padding(.horizontal, 24)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        sectionCard(sections[0])
                        sectionCard(sections[1])
                    }
                    sectionCard(sections[2])
                    AccountAllocationCard(totals: accountTotals)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .onAppear { appModel.refreshIncomeStatementItems() }
        .sheet(isPresented: $showingAdd) {
            StatementItemSheet(section: addingSection, parentID: addingParentID)
        }
        .sheet(item: $editingItem) { item in
            StatementItemSheet(item: item)
        }
    }
}

private struct IncomeStatementSectionCard: View {
    let title: String
    let items: [DatabaseManager.IncomeStatementItem]
    let value: (DatabaseManager.IncomeStatementItem) -> Double
    let onAdd: () -> Void
    let onAddChild: (DatabaseManager.IncomeStatementItem) -> Void
    let onEdit: (DatabaseManager.IncomeStatementItem) -> Void
    let onDelete: (DatabaseManager.IncomeStatementItem) -> Void
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.text(title, language: appLanguage)).font(.title3.weight(.semibold))
                Spacer()
                Button(action: onAdd) { Image(systemName: "plus") }.buttonStyle(.plain)
            }
            let roots = items.filter { $0.parentID == nil }
            if roots.isEmpty {
                Text(L10n.text("No items yet. Click + to add one.", language: appLanguage))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(roots) { item in row(item, level: 0) }
            }
            Divider()
            HStack {
                Text(L10n.text("Total", language: appLanguage)).fontWeight(.semibold)
                Spacer()
                Text(ntd(roots.reduce(0) { $0 + value($1) })).fontWeight(.bold)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(FinTrackTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(FinTrackTheme.border))
    }

    private func row(_ item: DatabaseManager.IncomeStatementItem, level: Int) -> AnyView {
        let hasChildren = items.contains { $0.parentID == item.id }
        return AnyView(VStack(alignment: .leading, spacing: 8) {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(level == 0 ? .headline : .callout)
                if !hasChildren, let accountName = item.accountName, !accountName.isEmpty {
                    Text(accountName).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(ntd(value(item)))
                .fontWeight(level == 0 ? .semibold : .regular)
        }
        .padding(.leading, CGFloat(level) * 18)
        .contentShape(Rectangle())
        .contextMenu {
            Button(L10n.text("Add child", language: appLanguage)) { onAddChild(item) }
            Button(L10n.text("Edit", language: appLanguage)) { onEdit(item) }
            Divider()
            Button(L10n.text("Delete", language: appLanguage), role: .destructive) { onDelete(item) }
        }
        ForEach(items.filter { $0.parentID == item.id }) { child in
            row(child, level: level + 1)
        }
        })
    }
}

private struct AccountAllocationCard: View {
    let totals: [(String, Double)]
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue

    var body: some View {
        let maximum = max(totals.map { abs($0.1) }.max() ?? 0, 1)
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("Account Allocation", language: appLanguage)).font(.title3.weight(.semibold))
            if totals.isEmpty {
                Text(L10n.text("Account allocation will appear after leaf items are added.", language: appLanguage))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(totals, id: \.0) { account, amount in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(account)
                            Spacer()
                            Text(ntd(amount)).fontWeight(.semibold)
                        }
                        GeometryReader { geometry in
                            Capsule()
                                .fill((amount < 0 ? FinTrackTheme.negative : FinTrackTheme.primary).opacity(0.72))
                                .frame(width: max(6, geometry.size.width * abs(amount) / maximum), height: 8)
                        }
                        .frame(height: 8)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(FinTrackTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(FinTrackTheme.border))
    }
}

private struct StatementItemSheet: View {
    let item: DatabaseManager.IncomeStatementItem?
    let section: String
    let parentID: Int64?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    @State private var name: String
    @State private var amount: String
    @State private var accountName: String
    @State private var errorMessage: String?

    init(section: String, parentID: Int64?) {
        self.item = nil
        self.section = section
        self.parentID = parentID
        _name = State(initialValue: "")
        _amount = State(initialValue: "0")
        _accountName = State(initialValue: "")
    }

    init(item: DatabaseManager.IncomeStatementItem) {
        self.item = item
        self.section = item.section
        self.parentID = item.parentID
        _name = State(initialValue: item.name)
        _amount = State(initialValue: String(item.amount))
        _accountName = State(initialValue: item.accountName ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text(item == nil ? "Add item" : "Edit item", language: appLanguage)).font(.title2.weight(.bold))
            TextField(L10n.text("Item name", language: appLanguage), text: $name).textFieldStyle(.roundedBorder)
            TextField(L10n.text("Amount (NTD)", language: appLanguage), text: $amount).textFieldStyle(.roundedBorder)
            TextField(L10n.text("Destination account (optional)", language: appLanguage), text: $accountName)
                .textFieldStyle(.roundedBorder)
            if !appModel.statementAccounts.isEmpty {
                Menu(L10n.text("Use existing account", language: appLanguage)) {
                    ForEach(appModel.statementAccounts, id: \.self) { existingAccount in
                        Button(existingAccount) { accountName = existingAccount }
                    }
                    Button(L10n.text("No linked account", language: appLanguage)) { accountName = "" }
                }
            }
            Text(L10n.text("Leaf items can share a destination account. Parent items with children are totaled from their children.", language: appLanguage))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(L10n.text("Cancel", language: appLanguage)) { dismiss() }
                Button(L10n.text("Save", language: appLanguage)) { save() }.buttonStyle(.borderedProminent)
            }
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let value = Double(amount) else {
            errorMessage = "Enter a name and valid amount."
            return
        }
        do {
            if let item {
                try appModel.updateIncomeStatementItem(id: item.id, name: name, amount: value, accountName: accountName)
            } else {
                try appModel.createIncomeStatementItem(section: section, parentID: parentID, name: name, amount: value, accountName: accountName)
            }
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

struct StatementCard: View {
    let section: StatementSection
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text(section.title, language: appLanguage))
                .font(.title3.weight(.semibold))
            ForEach(section.rows, id: \.name) { row in
                statementRow(row)
            }
            Divider()
            HStack {
                Text(L10n.text("Total", language: appLanguage)).fontWeight(.semibold)
                Spacer()
                Text(section.total).fontWeight(.bold)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(FinTrackTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(FinTrackTheme.border))
    }

    private func statementRow(_ row: StatementRow, indent: CGFloat = 0) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.text(row.name, language: appLanguage))
                    Spacer()
                    Text(row.value).fontWeight(indent == 0 ? .semibold : .regular)
                }
                .padding(.leading, indent)
                .foregroundStyle(indent == 0 ? .primary : .secondary)

                ForEach(row.children, id: \.name) { child in
                    statementRow(child, indent: indent + 18)
                }
            }
        )
    }
}

struct StatementSection {
    let title: String
    let rows: [StatementRow]
    let total: String
}

struct StatementRow {
    let name: String
    let value: String
    var children: [StatementRow] = []
}

struct SettingsCard: View {
    @Binding var showDetailChanges: Bool
    @Binding var appearanceMode: String
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    @AppStorage("performanceColorMode") private var performanceColorMode = "greenUp"
    @AppStorage("snapshotTime") private var snapshotTime = "23:00"

    private var snapshotOptions: [String] {
        (0..<24).map { String(format: "%02d:00", $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.text("Display", language: appLanguage))
                .font(.title3.weight(.semibold))
            Toggle(L10n.text("Show detail percentage changes", language: appLanguage), isOn: $showDetailChanges)
            Text(L10n.text("Turn this off to hide month-over-month percentages in asset and liability details.", language: appLanguage))
                .font(.callout)
                .foregroundStyle(.secondary)
            Picker(L10n.text("Language", language: appLanguage), selection: $appLanguage) {
                Text("English").tag(AppLanguage.english.rawValue)
                Text("繁體中文").tag(AppLanguage.traditionalChinese.rawValue)
            }
            .pickerStyle(.menu)
            .foregroundStyle(FinTrackTheme.textPrimary)
            .tint(FinTrackTheme.textPrimary)

            Picker(L10n.text("Performance colors", language: appLanguage), selection: $performanceColorMode) {
                Text(L10n.text("Green up / red down", language: appLanguage)).tag("greenUp")
                Text(L10n.text("Red up / green down", language: appLanguage)).tag("redUp")
                Text(L10n.text("Analog mode", language: appLanguage)).tag("analog")
            }
            .pickerStyle(.menu)
            .foregroundStyle(FinTrackTheme.textPrimary)
            .tint(FinTrackTheme.textPrimary)

            Picker(L10n.text("Daily snapshot time", language: appLanguage), selection: $snapshotTime) {
                ForEach(snapshotOptions, id: \.self) { time in
                    Text(time).tag(time)
                }
            }
            .pickerStyle(.menu)
            .foregroundStyle(FinTrackTheme.textPrimary)
            .tint(FinTrackTheme.textPrimary)
            .onChange(of: snapshotTime) { _, _ in
                SnapshotScheduler.install()
            }

            Picker(L10n.text("Appearance", language: appLanguage), selection: $appearanceMode) {
                Text(L10n.text("System", language: appLanguage)).tag("system")
                Text(L10n.text("Light", language: appLanguage)).tag("light")
                Text(L10n.text("Dark", language: appLanguage)).tag("dark")
            }
            .pickerStyle(.menu)
            .foregroundStyle(FinTrackTheme.textPrimary)
            .tint(FinTrackTheme.textPrimary)

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(FinTrackTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(FinTrackTheme.border))
    }
}

private struct HelpSectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(FinTrackTheme.textMuted)
            .tracking(0.8)
    }
}

private struct HelpIntroCard: View {
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(description)
                .foregroundStyle(FinTrackTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(FinTrackTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(FinTrackTheme.border))
    }
}

private struct HelpDefinitionSection: View {
    let rows: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                VStack(alignment: .leading, spacing: 5) {
                    Text(row.0)
                        .font(.body.weight(.semibold))
                    Text(row.1)
                        .font(.callout)
                        .foregroundStyle(FinTrackTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)

                if index < rows.count - 1 {
                    Rectangle()
                        .fill(FinTrackTheme.divider)
                        .frame(height: 1)
                }
            }
        }
    }
}

private struct HelpActionRow: View {
    let symbol: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(FinTrackTheme.primary)
                .frame(width: 22, height: 24, alignment: .center)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(description)
                    .font(.callout)
                    .foregroundStyle(FinTrackTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }
}

private struct HelpInfoCallout: View {
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle")
                .foregroundStyle(FinTrackTheme.info)
                .font(.title3)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(description)
                    .font(.callout)
                    .foregroundStyle(FinTrackTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(FinTrackTheme.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(FinTrackTheme.primary.opacity(0.25)))
    }
}

struct HelpView: View {
    let page: String
    let onBack: () -> Void
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.title3.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .help(helpText("Back", "返回"))
                    Spacer()
                }

                switch page {
                case "Overview": overviewHelp
                case "Portfolio": portfolioHelp
                case "Dividends": dividendsHelp
                case "Recurring Investment": recurringHelp
                case "Foreign Currency": foreignCurrencyHelp
                case "Income Statement": incomeStatementHelp
                case "Settings": settingsHelp
                default: recurringHoldingHelp
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(24)
        }
    }

    private func helpText(_ english: String, _ chinese: String) -> String {
        appLanguage == AppLanguage.traditionalChinese.rawValue ? chinese : english
    }

    private func helpHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(helpText(title, title == "Portfolio" ? "投資組合" : title == "Dividends" ? "股利" : title == "Recurring Investment" ? "定期定額" : title == "Foreign Currency" ? "外幣" : title == "Income Statement" ? "損益表" : title == "Settings" ? "設定" : "投資紀錄"))
                .font(.title2.weight(.bold))
            Text(helpText(subtitle, subtitle == "See how your investments are distributed and performing." ? "查看投資配置與整體表現。" : subtitle == "Review dividend income from your holdings." ? "查看持有資產帶來的股利收入。" : subtitle == "Plan recurring purchases and keep each purchase record in one place." ? "規劃定期定額，並集中管理每次投資紀錄。" : subtitle == "Track foreign-currency balances, rates, and transactions." ? "追蹤外幣餘額、匯率與交易紀錄。" : subtitle == "Organize income, expenses, and savings in one view." ? "在同一個頁面整理收入、支出與儲蓄。" : subtitle == "Adjust how FinTrack looks and behaves." ? "調整 FinTrack 的外觀與使用方式。" : "查看這項定期定額標的的投資紀錄。"))
                .foregroundStyle(FinTrackTheme.textSecondary)
        }
    }

    private var portfolioHelp: some View {
        VStack(alignment: .leading, spacing: 24) {
            helpHeader("Portfolio", "See how your investments are distributed and performing.")
            HelpSectionLabel(text: helpText("AT A GLANCE", "快速了解"))
            HelpDefinitionSection(rows: [
                (helpText("Total P&L", "總損益"), helpText("Your overall gain or loss based on recorded cost and current value.", "依照已記錄成本與目前市值計算整體獲利或損失。")),
                (helpText("Today", "今日"), helpText("The change from the latest regular-session price to the previous regular trading session's close. During regular hours it can update; after close it keeps the completed session result.", "以最新正常交易時段價格，減去前一個正常交易日的收盤價。交易時段內會更新，收盤後會保留該交易日的完成結果。")),
                (helpText("Market Value", "目前市值"), helpText("The current estimated value of all holdings.", "所有持股目前的估計價值。"))
            ])
            HelpSectionLabel(text: helpText("ALLOCATION", "資產配置"))
            HelpIntroCard(title: helpText("Your investment mix", "你的投資配置"), description: helpText("The chart ranks holdings by portfolio weight. Colors represent ranking order, not profit or loss.", "圖表會依持股比重排序；顏色代表比重排名，不代表損益。"))
            HelpSectionLabel(text: helpText("HOLDINGS", "持股明細"))
            HelpDefinitionSection(rows: [
                (helpText("Last", "現價"), helpText("The latest recorded market price.", "最近記錄的市場價格。")),
                (helpText("Value", "市值"), helpText("Shares multiplied by the latest price.", "股數乘以最近價格。")),
                (helpText("P&L", "損益"), helpText("The difference between current value and recorded cost.", "目前市值與已記錄成本之間的差額。"))
            ])
            HelpSectionLabel(text: helpText("MARKET DATA", "市場資料"))
            HelpIntroCard(title: helpText("Regular-session prices", "正常交易時段價格"), description: helpText("FinTrack uses regular-session prices only. Prices update automatically while the app is active; if the stream or network is unavailable, the latest valid local data is used.", "FinTrack 只使用正常交易時段價格。App 開啟時會自動更新；若串流或網路無法使用，則沿用本機最近的有效資料。"))
            HelpActionRow(symbol: "plus", title: helpText("Add a holding", "新增持股"), description: helpText("Use + in Holdings, then search for a symbol and enter its shares and cost.", "在持股區按下＋，搜尋標的後填入股數與成本。"))
        }
    }

    private var dividendsHelp: some View {
        VStack(alignment: .leading, spacing: 24) {
            helpHeader("Dividends", "Review dividend income from your holdings.")
            HelpSectionLabel(text: helpText("WHAT YOU SEE", "這裡會顯示什麼"))
            HelpIntroCard(title: helpText("Dividend records", "股利紀錄"), description: helpText("Each row shows the security, the date you received the dividend, and the amount received. Values are kept in their original currency.", "每一列會顯示標的、你收到股利的日期與收到的金額，並保留原始幣別。"))
            HelpSectionLabel(text: helpText("HOW TO USE IT", "使用方式"))
            HelpDefinitionSection(rows: [
                (helpText("Add", "新增"), helpText("Click + to choose a holding and record a dividend payment.", "按下＋選擇持股並記錄股利入帳。")),
                (helpText("Edit or delete", "編輯或刪除"), helpText("Right-click a record to change it or remove it.", "在紀錄上按右鍵即可編輯或刪除。")),
                (helpText("Currency", "幣別"), helpText("The currency follows the holding, so the amount is not silently converted.", "幣別會跟隨持股，不會在沒有提示的情況下轉換金額。"))
            ])
        }
    }

    private var recurringHelp: some View {
        VStack(alignment: .leading, spacing: 24) {
            helpHeader("Recurring Investment", "Plan recurring purchases and keep each purchase record in one place.")
            HelpSectionLabel(text: helpText("START HERE", "從這裡開始"))
            HelpIntroCard(title: helpText("A plan and its actual purchases", "計畫與實際投資"), description: helpText("A recurring rule describes when and how much you plan to invest. The purchase records below it are the transactions that actually happened.", "定期定額規則描述預計何時、投入多少；下方投資紀錄則是實際發生的每一筆交易。"))
            HelpSectionLabel(text: helpText("RECORDS", "紀錄"))
            HelpDefinitionSection(rows: [
                (helpText("Schedules", "排程"), helpText("Shows the planned amount, frequency, and day of the month.", "顯示預計金額、頻率與每月執行日。")),
                (helpText("Purchases", "投資紀錄"), helpText("Add the actual date, shares, and amount after a purchase is completed.", "投資完成後，新增實際日期、股數與金額。")),
                (helpText("Funding account", "扣款帳戶"), helpText("For foreign-currency investments, choose a matching foreign-currency account to update its balance and create a transaction record.", "外幣投資可選擇相同幣別的外幣帳戶，系統會同步更新餘額並建立交易紀錄。"))
            ])
            HelpActionRow(symbol: "plus", title: helpText("Add an actual purchase", "新增實際投資"), description: helpText("Open a recurring investment item, then click + in Purchases. The schedule does not place orders automatically.", "開啟定期定額標的，再於投資紀錄旁按下＋；排程本身不會自動下單。"))
            HelpInfoCallout(title: helpText("Important", "重要提醒"), description: helpText("A schedule is a plan only. Record the actual shares, amount, and date after the purchase is completed.", "排程只是投資計畫；完成實際交易後，仍需手動記錄股數、金額與日期。"))
        }
    }

    private var recurringHoldingHelp: some View {
        VStack(alignment: .leading, spacing: 24) {
            helpHeader("Recurring Investment", "View this recurring investment's purchase history.")
            HelpSectionLabel(text: helpText("THIS INVESTMENT", "這項投資"))
            HelpIntroCard(title: helpText("Schedules and purchases", "排程與投資紀錄"), description: helpText("Schedules show your plan. Purchases show what you actually invested, including the date, shares, and amount.", "排程顯示你的計畫；投資紀錄顯示實際投入的日期、股數與金額。"))
            HelpSectionLabel(text: helpText("MANAGE RECORDS", "管理紀錄"))
            HelpDefinitionSection(rows: [
                (helpText("Add", "新增"), helpText("Click + to record a completed purchase.", "按下＋記錄已完成的投資。")),
                (helpText("Edit or delete", "編輯或刪除"), helpText("Right-click a purchase to edit or delete it. Related balances are adjusted together.", "在投資紀錄上按右鍵即可編輯或刪除，相關餘額也會同步調整。")),
                (helpText("Schedule vs purchase", "排程與實際投資"), helpText("Editing a schedule changes the plan; it does not change existing purchase records.", "編輯排程只會改變投資計畫，不會改變既有的實際投資紀錄。"))
            ])
        }
    }

    private var foreignCurrencyHelp: some View {
        VStack(alignment: .leading, spacing: 24) {
            helpHeader("Foreign Currency", "Track foreign-currency balances, rates, and transactions.")
            HelpSectionLabel(text: helpText("BALANCES", "餘額"))
            HelpDefinitionSection(rows: [
                (helpText("Balance", "餘額"), helpText("The amount currently held in each foreign currency.", "目前持有的各種外幣金額。")),
                (helpText("Rate", "匯率"), helpText("The latest NTD rate used for the displayed equivalent value.", "用來計算新台幣等價金額的最新匯率。")),
                (helpText("NTD value", "新台幣等價"), helpText("The foreign-currency balance converted to NTD.", "將外幣餘額換算成新台幣後的金額。"))
            ])
            HelpSectionLabel(text: helpText("TRANSACTIONS", "交易紀錄"))
            HelpIntroCard(title: helpText("Keep the money trail clear", "保留完整資金軌跡"), description: helpText("Use Exchange for a conversion that has an NTD amount and rate. Use Other for spending, investing, or income that only changes the foreign balance.", "換匯請選擇換匯並填寫新台幣金額與匯率；支出、投資或收入等只改變外幣餘額的情況，請選擇其他。"))
            HelpActionRow(symbol: "plus", title: helpText("Add a transaction", "新增交易"), description: helpText("Click + beside Transactions. A negative foreign amount represents money leaving the account. Balances and rates refresh when market data is updated.", "按下交易紀錄旁的＋；原幣金額為負數代表資金離開帳戶。市場資料更新時，餘額與匯率也會刷新。"))
        }
    }

    private var incomeStatementHelp: some View {
        VStack(alignment: .leading, spacing: 24) {
            helpHeader("Income Statement", "Organize income, expenses, and savings in one view.")
            HelpSectionLabel(text: helpText("THE BIG PICTURE", "整體概況"))
            HelpDefinitionSection(rows: [
                (helpText("Total Income", "總收入"), helpText("All income items recorded for the selected period.", "所選期間內記錄的所有收入。")),
                (helpText("Total Expenses", "總支出"), helpText("All expense items recorded for the selected period.", "所選期間內記錄的所有支出。")),
                (helpText("Monthly Profit", "月結餘"), helpText("Income minus expenses for the period.", "該期間的收入減去支出。"))
            ])
            HelpSectionLabel(text: helpText("ORGANIZE YOUR MONEY", "整理你的金錢流向"))
            HelpIntroCard(title: helpText("Groups and details", "分類與明細"), description: helpText("Use a group for a broad category, then add details underneath it. The totals of a group come from its details.", "先用大分類整理方向，再在下面建立明細；有明細的大分類會依明細自動加總。"))
            HelpActionRow(symbol: "plus", title: helpText("Add a detail", "新增明細"), description: helpText("Use + in the relevant section. Right-click an item to edit or delete it.", "在對應區塊按下＋；在項目上按右鍵即可編輯或刪除。"))
        }
    }

    private var settingsHelp: some View {
        VStack(alignment: .leading, spacing: 24) {
            helpHeader("Settings", "Adjust how FinTrack looks and behaves.")
            HelpSectionLabel(text: helpText("DISPLAY", "顯示"))
            HelpDefinitionSection(rows: [
                (helpText("Detail percentages", "明細百分比"), helpText("Show or hide month-over-month changes in asset and liability details.", "顯示或隱藏資產與負債明細的月增減百分比。")),
                (helpText("Language", "語言"), helpText("Switch between English and Traditional Chinese.", "切換英文與繁體中文。")),
                (helpText("Performance colors", "漲跌顏色"), helpText("Choose how positive and negative performance colors are presented.", "選擇正負績效的顏色呈現方式。")),
                (helpText("Daily snapshot time", "每日快照時間"), helpText("Choose when FinTrack automatically records the net-worth snapshot. This setting does not define the Portfolio TODAY calculation time.", "選擇 FinTrack 自動記錄淨值快照的時間；這項設定不會決定投資組合 TODAY 的計算時間。")),
                (helpText("Background schedule", "背景排程"), helpText("The Mac must be powered on and FinTrack must be allowed to run in the user's active session. If the scheduled run is missed, it can be recovered when FinTrack runs again.", "Mac 必須開機，且 FinTrack 能在使用者目前的工作階段執行。若錯過排程，之後再次執行 FinTrack 時可以補回。")),
                (helpText("Appearance", "外觀"), helpText("Choose Light, Dark, or System. System follows the Mac's current appearance setting.", "選擇淺色、深色或跟隨系統；跟隨系統會使用 Mac 目前的外觀設定。"))
            ])
        }
    }

    private var overviewHelp: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(L10n.text("Overview", language: appLanguage))
                .font(.title2.weight(.bold))
            Text(L10n.text("Understand your overall financial position.", language: appLanguage))
                .foregroundStyle(FinTrackTheme.textSecondary)

            HelpSectionLabel(text: L10n.text("OVERVIEW", language: appLanguage))
            HelpIntroCard(
                title: L10n.text("Your financial picture", language: appLanguage),
                description: L10n.text("Overview brings your assets, liabilities, investments, and cash together in one financial snapshot.", language: appLanguage)
            )

            HelpSectionLabel(text: L10n.text("KEY METRICS", language: appLanguage))
            HelpDefinitionSection(rows: [
                (L10n.text("Total Assets", language: appLanguage), L10n.text("Everything you currently own, converted to NTD.", language: appLanguage)),
                (L10n.text("Total Liabilities", language: appLanguage), L10n.text("Money you currently owe.", language: appLanguage)),
                (L10n.text("Net Worth", language: appLanguage), L10n.text("Total Assets − Total Liabilities", language: appLanguage))
            ])

            HelpSectionLabel(text: L10n.text("YOUR DETAILS", language: appLanguage))
            HelpDefinitionSection(rows: [
                (L10n.text("Liquid Assets", language: appLanguage), L10n.text("Cash and other readily available funds.", language: appLanguage)),
                (L10n.text("Liquid Investments", language: appLanguage), L10n.text("Investments that can generally be sold.", language: appLanguage)),
                (L10n.text("Long-term Investment", language: appLanguage), L10n.text("Assets intended to be held longer.", language: appLanguage))
            ])

            HelpSectionLabel(text: L10n.text("CHANGES OVER TIME", language: appLanguage))
            HelpDefinitionSection(rows: [
                (L10n.text("Monthly Change", language: appLanguage), L10n.text("Compares the current value with the previous month. You can hide these percentages in Settings.", language: appLanguage))
            ])

            HelpSectionLabel(text: helpText("NET WORTH HISTORY", "淨值歷史"))
            HelpDefinitionSection(rows: [
                (helpText("Snapshot", "快照"), helpText("Records your current net worth as a historical data point.", "將目前淨值記錄成一筆歷史資料。")),
                (helpText("Same-day snapshots", "同日快照"), helpText("Creating more than one snapshot on the same day does not create multiple records. The latest snapshot replaces that day's data.", "同一天建立多次快照不會產生多筆資料，最新的快照會覆蓋當天資料。")),
                (helpText("Chart ranges", "圖表區間"), helpText("Choose a time range. Longer ranges can be scrolled horizontally to view older points.", "選擇要查看的時間區間；較長的區間可以左右滑動查看較早的資料。")),
                (helpText("Chart details", "圖表資訊"), helpText("Move the pointer onto a data point to see its net worth and date.", "將游標移到資料點上，即可查看該日的淨值與日期。")),
                (helpText("Automatic snapshots", "自動快照"), helpText("The scheduled snapshot records net worth automatically. The Snapshot button creates one immediately.", "定時快照會自動記錄淨值；按下快照按鈕則會立即建立一筆資料。"))
            ])

            HelpSectionLabel(text: L10n.text("ADDING INFORMATION", language: appLanguage))
            VStack(alignment: .leading, spacing: 4) {
                HelpActionRow(symbol: "plus", title: L10n.text("Add an asset or liability", language: appLanguage), description: L10n.text("Use the + button in the corresponding details section.", language: appLanguage))
                HelpActionRow(symbol: "chart.pie", title: L10n.text("Add investments", language: appLanguage), description: L10n.text("Open Portfolio from the sidebar.", language: appLanguage))
                HelpActionRow(symbol: "globe.americas.fill", title: L10n.text("Add foreign currency", language: appLanguage), description: L10n.text("Open Foreign Currency from the sidebar.", language: appLanguage))
            }

            HelpInfoCallout(
                title: L10n.text("Market data", language: appLanguage),
                description: L10n.text("FinTrack refreshes market prices and exchange rates when possible. Saved local data remains available offline.", language: appLanguage)
            )
        }
    }
}

struct RecurringInvestmentView: View {
    @EnvironmentObject private var appModel: AppModel
    @Binding var selectedPage: String
    @State private var showingAddRule = false
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L10n.text("Recurring Rules", language: appLanguage))
                    .font(.title2.weight(.semibold))
                Spacer()
                Button(action: { showingAddRule = true }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .font(.title3.weight(.semibold))
            }

            if appModel.recurringRecords.isEmpty {
                ContentUnavailableView(
                    L10n.text("No recurring rules", language: appLanguage),
                    systemImage: "calendar.badge.clock",
                    description: Text(L10n.text("Add a rule to plan your recurring investments.", language: appLanguage))
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(appModel.recurringRecords) { rule in
                            Button {
                                selectedPage = rule.securityName
                            } label: {
                                recurringRuleRow(rule)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                    }
                    .background(FinTrackTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(FinTrackTheme.border))
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .sheet(isPresented: $showingAddRule) {
            AddRecurringRuleSheet()
        }
    }

    private func recurringRuleRow(_ rule: DatabaseManager.RecurringRecord) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.securityName).font(.headline)
                Text("\(rule.symbol) · " + rule.schedules.map { "\(L10n.text($0.frequency, language: appLanguage)) \($0.executionDay)\(L10n.text("day", language: appLanguage))" }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(money(rule.plannedAmount, currency: rule.currency)).font(.headline)
                Text(L10n.text("Click to view investments", language: appLanguage)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

struct RecurringHoldingDetailView: View {
    let rule: DatabaseManager.RecurringRecord
    @EnvironmentObject private var appModel: AppModel
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    @State private var showingAddPurchase = false
    @State private var editingSchedule: DatabaseManager.RecurringSchedule?
    @State private var editingPurchase: DatabaseManager.RecurringPurchaseRecord?
    @State private var pendingDeletePurchase: DatabaseManager.RecurringPurchaseRecord?
    @State private var purchases: [DatabaseManager.RecurringPurchaseRecord] = []

    var body: some View {
        let totalAmount = purchases.reduce(0) { $0 + $1.amount }
        let totalShares = purchases.reduce(0) { $0 + $1.shares }
        let lastPurchaseDate = purchases.first?.tradeDate ?? "—"

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                PortfolioMetricCard(
                    title: "TOTAL CONTRIBUTED",
                    value: purchases.isEmpty ? "—" : money(totalAmount, currency: rule.currency),
                    detail: "\(purchases.count) \(L10n.text("purchases", language: appLanguage))",
                    tint: .primary
                )
                PortfolioMetricCard(
                    title: "TOTAL SHARES",
                    value: purchases.isEmpty ? "—" : String(format: "%.2f", totalShares),
                    detail: rule.symbol,
                    tint: .primary
                )
                PortfolioMetricCard(
                    title: "LAST PURCHASE",
                    value: lastPurchaseDate,
                    detail: L10n.text(rule.frequency, language: appLanguage),
                    tint: .primary
                )
            }

            Rectangle()
                .fill(FinTrackTheme.divider)
                .frame(height: 1)
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("SCHEDULES", language: appLanguage)).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                ForEach(rule.schedules) { schedule in
                    HStack {
                        Text("\(money(schedule.plannedAmount, currency: schedule.currency)) · \(L10n.text(schedule.frequency, language: appLanguage)) · \(schedule.executionDay)\(L10n.text("day", language: appLanguage))")
                        Spacer()
                        Button {
                            editingSchedule = schedule
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
            .background(FinTrackTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(FinTrackTheme.border))

            VStack(spacing: 0) {
                HStack {
                    Text(L10n.text("PURCHASES", language: appLanguage)).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Spacer()
                    Button(action: { showingAddPurchase = true }) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .font(.callout.weight(.semibold))
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

                HStack {
                    Text(L10n.text("DATE", language: appLanguage)).frame(maxWidth: .infinity, alignment: .leading)
                    Text(L10n.text("SHARES", language: appLanguage)).frame(width: 120, alignment: .trailing)
                    Text(L10n.text("AMOUNT", language: appLanguage)).frame(width: 140, alignment: .trailing)
                    Color.clear.frame(width: 58)
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

                VStack(spacing: 0) {
                        if purchases.isEmpty {
                            Text(L10n.text("No purchases recorded. Click + to add the actual transaction.", language: appLanguage))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 160)
                        } else {
                            ForEach(purchases) { purchase in
                                HStack {
                                    Text(purchase.tradeDate).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(String(format: "%.2f", purchase.shares)).frame(width: 120, alignment: .trailing)
                                    Text(money(purchase.amount, currency: purchase.currency))
                                        .frame(width: 140, alignment: .trailing)
                                    Color.clear.frame(width: 58)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 11)
                                .contentShape(Rectangle())
                                .contextMenu {
                                    Button("Edit") { editingPurchase = purchase }
                                    Divider()
                                    Button("Delete", role: .destructive) { pendingDeletePurchase = purchase }
                                }
                            }
                        }
                }
            }
            .background(FinTrackTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(FinTrackTheme.border))
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .id(rule.holdingID)
        .task(id: rule.holdingID) {
            purchases = appModel.recurringPurchases(holdingID: rule.holdingID)
        }
        .sheet(isPresented: $showingAddPurchase) {
            AddRecurringPurchaseSheet(rule: rule) {
                purchases = appModel.recurringPurchases(holdingID: rule.holdingID)
            }
        }
        .sheet(item: $editingSchedule) { schedule in
            EditRecurringRuleSheet(schedule: schedule)
        }
        .sheet(item: $editingPurchase) { purchase in
            EditRecurringPurchaseSheet(purchase: purchase) {
                purchases = appModel.recurringPurchases(holdingID: rule.holdingID)
            }
        }
        .alert(item: $pendingDeletePurchase) { purchase in
            Alert(
                title: Text("Delete purchase?"),
                message: Text("This will also reverse its shares and cost from the holding."),
                primaryButton: .destructive(Text("Delete")) {
                    do {
                        try appModel.deleteRecurringPurchase(id: purchase.id)
                        purchases = appModel.recurringPurchases(holdingID: rule.holdingID)
                    } catch { }
                },
                secondaryButton: .cancel()
            )
        }
    }
}

struct EditRecurringRuleSheet: View {
    let schedule: DatabaseManager.RecurringSchedule
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel
    @State private var plannedAmount: String
    @State private var currency: String
    @State private var frequency: String
    @State private var executionDay: Int
    @State private var errorMessage: String?

    init(schedule: DatabaseManager.RecurringSchedule) {
        self.schedule = schedule
        _plannedAmount = State(initialValue: String(schedule.plannedAmount))
        _currency = State(initialValue: schedule.currency)
        _frequency = State(initialValue: schedule.frequency)
        _executionDay = State(initialValue: schedule.executionDay)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Recurring Rule").font(.title2.weight(.bold))
            TextField("Planned amount", text: $plannedAmount).textFieldStyle(.roundedBorder)
            Picker("Currency", selection: $currency) {
                Text("NTD").tag("NTD")
                Text("USD").tag("USD")
                Text("JPY").tag("JPY")
            }
            .pickerStyle(.menu)
            Picker("Frequency", selection: $frequency) {
                Text("Monthly").tag("monthly")
                Text("Weekly").tag("weekly")
            }
            .pickerStyle(.menu)
            Stepper("Execution day: \(executionDay)", value: $executionDay, in: 1...31)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }.buttonStyle(.borderedProminent)
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func save() {
        guard let amount = Double(plannedAmount), amount > 0 else {
            errorMessage = "Enter an amount greater than zero."
            return
        }
        do {
            try appModel.updateRecurringRule(
                id: schedule.id,
                plannedAmount: amount,
                currency: currency,
                frequency: frequency,
                executionDay: executionDay
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AddRecurringPurchaseSheet: View {
    let rule: DatabaseManager.RecurringRecord
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel
    @State private var tradeDate = Self.isoDateFormatter.string(from: Date())
    @State private var shares = ""
    @State private var amount = ""
    @State private var fundingAssetID: Int64 = 0
    @State private var errorMessage: String?

    private var fundingAssets: [DatabaseManager.AssetRecord] {
        appModel.assets.filter { $0.category == "Foreign Currency" && $0.currency == rule.currency }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Record Purchase").font(.title2.weight(.bold))
            Text(rule.securityName).foregroundStyle(.secondary)
            TextField("Purchase date (yyyy-MM-dd)", text: $tradeDate)
                .textFieldStyle(.roundedBorder)
            TextField("Shares", text: $shares).textFieldStyle(.roundedBorder)
            TextField("Amount (\(rule.currency))", text: $amount).textFieldStyle(.roundedBorder)
            Picker("Funding account", selection: $fundingAssetID) {
                Text("No linked account").tag(Int64(0))
                ForEach(fundingAssets) { asset in
                    Text("\(asset.name) (\(asset.currency))").tag(asset.id)
                }
            }
            .pickerStyle(.menu)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }.buttonStyle(.borderedProminent)
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func save() {
        guard let shareValue = Double(shares), shareValue > 0,
              let amountValue = Double(amount), amountValue > 0 else {
            errorMessage = "Enter shares and amount greater than zero."
            return
        }
        guard Self.isoDateFormatter.date(from: tradeDate) != nil else {
            errorMessage = "Enter the date as yyyy-MM-dd."
            return
        }
        do {
            try appModel.addRecurringPurchase(
                holdingID: rule.holdingID,
                tradeDate: tradeDate,
                shares: shareValue,
                amount: amountValue,
                currency: rule.currency,
                fundingAssetID: fundingAssetID == 0 ? nil : fundingAssetID
            )
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

struct EditRecurringPurchaseSheet: View {
    let purchase: DatabaseManager.RecurringPurchaseRecord
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel
    @State private var tradeDate: String
    @State private var shares: String
    @State private var amount: String
    @State private var fundingAssetID: Int64
    @State private var errorMessage: String?

    private var fundingAssets: [DatabaseManager.AssetRecord] {
        appModel.assets.filter { $0.category == "Foreign Currency" && $0.currency == purchase.currency }
    }

    init(purchase: DatabaseManager.RecurringPurchaseRecord, onSaved: @escaping () -> Void) {
        self.purchase = purchase
        self.onSaved = onSaved
        _tradeDate = State(initialValue: purchase.tradeDate)
        _shares = State(initialValue: String(purchase.shares))
        _amount = State(initialValue: String(purchase.amount))
        _fundingAssetID = State(initialValue: purchase.fundingAssetID ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Purchase").font(.title2.weight(.bold))
            TextField("Purchase date (yyyy-MM-dd)", text: $tradeDate)
                .textFieldStyle(.roundedBorder)
            TextField("Shares", text: $shares)
                .textFieldStyle(.roundedBorder)
            TextField("Amount (\(purchase.currency))", text: $amount)
                .textFieldStyle(.roundedBorder)
            Picker("Funding account", selection: $fundingAssetID) {
                Text("No linked account").tag(Int64(0))
                ForEach(fundingAssets) { asset in
                    Text("\(asset.name) (\(asset.currency))").tag(asset.id)
                }
            }
            .pickerStyle(.menu)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }.buttonStyle(.borderedProminent)
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func save() {
        guard Self.isoDateFormatter.date(from: tradeDate) != nil,
              let shareValue = Double(shares), shareValue > 0,
              let amountValue = Double(amount), amountValue > 0 else {
            errorMessage = "Enter a valid date, shares, and amount."
            return
        }
        do {
            try appModel.updateRecurringPurchase(
                id: purchase.id,
                tradeDate: tradeDate,
                shares: shareValue,
                amount: amountValue,
                fundingAssetID: fundingAssetID == 0 ? nil : fundingAssetID
            )
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

struct AddRecurringRuleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedHoldingID: Int64?
    @State private var plannedAmount = ""
    @State private var currency = "NTD"
    @State private var frequency = "monthly"
    @State private var executionDay = 1
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Recurring Rule").font(.title2.weight(.bold))

            Picker("Holding", selection: $selectedHoldingID) {
                Text("Select a holding").tag(nil as Int64?)
                ForEach(appModel.holdingRecords) { holding in
                    Text("\(holding.securityName) (\(holding.symbol))").tag(holding.id as Int64?)
                }
            }
            .pickerStyle(.menu)

            TextField("Planned amount", text: $plannedAmount)
                .textFieldStyle(.roundedBorder)
            Picker("Currency", selection: $currency) {
                Text("NTD").tag("NTD")
                Text("USD").tag("USD")
                Text("JPY").tag("JPY")
            }
            .pickerStyle(.menu)
            Picker("Frequency", selection: $frequency) {
                Text("Monthly").tag("monthly")
                Text("Weekly").tag("weekly")
            }
            .pickerStyle(.menu)
            Stepper("Execution day: \(executionDay)", value: $executionDay, in: 1...31)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }.buttonStyle(.borderedProminent)
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func save() {
        guard let selectedHoldingID,
              let amount = Double(plannedAmount), amount > 0 else {
            errorMessage = "Select a holding and enter an amount greater than zero."
            return
        }
        do {
            try appModel.createRecurringRule(
                holdingID: selectedHoldingID,
                plannedAmount: amount,
                currency: currency,
                frequency: frequency,
                executionDay: executionDay,
                startDate: ISO8601DateFormatter().string(from: Date())
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let change: String
    var warning = false
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
            Text(L10n.text(title, language: appLanguage)).foregroundStyle(FinTrackTheme.textSecondary)
                if warning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(FinTrackTheme.warning)
                        .accessibilityLabel("Warning")
                }
            }
            Text(value).font(.title2.weight(.bold)).foregroundStyle(warning ? FinTrackTheme.negative : FinTrackTheme.textPrimary)
            Text(change.replacingOccurrences(of: " vs last month", with: appLanguage == AppLanguage.traditionalChinese.rawValue ? " 較上月" : " vs last month"))
                .font(.caption).foregroundStyle(warning || change.hasPrefix("-") ? FinTrackTheme.negative : FinTrackTheme.positive)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(FinTrackTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(FinTrackTheme.border))
    }
}

struct DetailCard: View {
    let title: String
    let showChanges: Bool
    let onAdd: (() -> Void)?
    let sections: [DetailSection]
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L10n.text(title, language: appLanguage)).font(.title3.weight(.semibold))
                Spacer()
                if let onAdd {
                    Button("+ Add", action: onAdd)
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                        .font(.callout.weight(.semibold))
                }
            }
            ForEach(Array(sections.enumerated()), id: \.offset) { sectionIndex, section in
                if sectionIndex > 0 {
                    Divider()
                        .opacity(0.3)
                }
                detailRow(name: section.title, value: section.value, change: section.change, showChange: showChanges)
                    .fontWeight(.semibold)

                    ForEach(section.children, id: \.name) { child in
                        detailRow(name: child.name, value: child.value, change: child.change, showChange: showChanges)
                        .padding(.leading, 18)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                        .contextMenu {
                            if let onEdit = child.onEdit {
                                Button("Edit", action: onEdit)
                            }
                            if let onDelete = child.onDelete {
                                Button("Delete", role: .destructive, action: onDelete)
                            }
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(FinTrackTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(FinTrackTheme.border))
    }

    private func detailRow(name: String, value: String, change: String, showChange: Bool) -> some View {
        HStack(alignment: .top) {
            Text(L10n.text(name, language: appLanguage))
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(value)
                    .foregroundStyle(showChange ? changeColor(change) : FinTrackTheme.textPrimary)
                if showChange {
                    Text(change)
                        .font(.caption)
                        .foregroundStyle(changeColor(change))
                }
            }
        }
    }

    private func changeColor(_ change: String) -> Color {
        change.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("-")
            ? FinTrackTheme.negative
            : FinTrackTheme.positive
    }
}

struct DetailSection {
    let title: String
    let value: String
    let change: String
    var children: [DetailRow] = []
}

struct DetailRow {
    let name: String
    let value: String
    let change: String
    let onDelete: (() -> Void)?
    let onEdit: (() -> Void)?

    init(
        name: String,
        value: String,
        change: String,
        onDelete: (() -> Void)? = nil,
        onEdit: (() -> Void)? = nil
    ) {
        self.name = name
        self.value = value
        self.change = change
        self.onDelete = onDelete
        self.onEdit = onEdit
    }
}
