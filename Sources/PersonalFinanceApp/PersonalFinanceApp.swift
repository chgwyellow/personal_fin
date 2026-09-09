import AppKit
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
        .windowResizability(.contentSize)
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
    private let databaseManager: DatabaseManager?
    private let marketDataClient = MarketDataClient()

    init() {
        databaseManager = try? DatabaseManager()
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

    func addRecurringPurchase(holdingID: Int64, tradeDate: String, shares: Double, amount: Double, currency: String) throws {
        guard let databaseManager else { throw DatabaseManager.DatabaseError.openFailed("Database is unavailable") }
        try databaseManager.addRecurringPurchase(holdingID: holdingID, tradeDate: tradeDate, shares: shares, amount: amount, currency: currency)
        refreshAssets()
        refreshHoldings()
        refreshPortfolioTotals()
        refreshAllocations()
        refreshRecurringInvestments()
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
        let records = holdingRecords
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())
        var dailyQuotes: [(DatabaseManager.HoldingRecord, MarketDataClient.Quote)] = []

        for holding in records {
            do {
                if let quote = try await marketDataClient.fetchQuote(symbol: holding.symbol) {
                    try databaseManager.insertMarketPrice(
                        symbol: holding.symbol,
                        market: holding.market,
                        price: quote.price,
                        currency: quote.currency,
                        observedAt: timestamp,
                        source: "Yahoo Finance"
                    )
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

        var todayTotal = 0.0
        var hasTodayData = false
        for (holding, quote) in dailyQuotes {
            guard let previousClose = quote.previousClose else { continue }
            let rate: Double
            if holding.currency == "NTD" {
                rate = 1
            } else {
                rate = (try? databaseManager.latestExchangeRate(base: holding.currency, quote: "NTD")) ?? 0
            }
            todayTotal += (quote.price - previousClose) * holding.shares * rate
            hasTodayData = true
        }
        todayPLNTD = hasTodayData ? todayTotal : nil

        refreshAssets()
        refreshHoldings()
        refreshPortfolioTotals()
        refreshAllocations()
        saveDailySnapshotIfDue()
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
        formatter.dateFormat = "yyyy-MM-dd"
        do {
            try databaseManager.saveSnapshot(
                date: formatter.string(from: Date()),
                assets: assetTotals,
                liabilities: liabilityTotals
            )
        } catch {
            NSLog("FinTrack snapshot save failed: %@", error.localizedDescription)
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
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        initializeDatabase()
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
        "BALANCE": "餘額", "RATE": "匯率", "NTD VALUE": "新台幣等價", "CURRENCY": "幣別", "SECURITY": "標的", "DATE": "日期", "AMOUNT": "金額", "TRANSACTIONS": "交易紀錄", "PURPOSE": "用途", "FOREIGN AMOUNT": "原幣金額", "NTD": "新台幣", "SHARES": "股數",
        "Add foreign-currency transaction": "新增外幣交易", "Transaction type": "交易類型", "Exchange": "換匯", "Exchange direction": "換匯方向", "Buy foreign currency": "買入外幣", "Sell foreign currency back to NTD": "賣出外幣換回新台幣", "Other purpose": "其他用途", "Original currency": "原幣別", "Foreign amount": "原幣金額", "Foreign amount (+ income / - expense)": "原幣金額（收入＋／支出－）", "NTD amount": "新台幣金額", "Rate (NTD per unit)": "匯率（每單位新台幣）", "NTD amount (exchange only)": "新台幣金額（僅換匯）", "Rate (NTD per unit, exchange only)": "匯率（每單位新台幣，僅換匯）", "Purpose": "用途", "Date": "日期", "Exchange transactions require NTD amount and rate.": "換匯交易需要填寫新台幣金額與匯率。", "Other transactions only change the foreign-currency balance; NTD amount and rate are not required.": "其他交易只會變更外幣餘額，不需要填寫新台幣金額與匯率。", "Enter a currency and positive foreign amount.": "請輸入幣別與正的原幣金額。", "Enter a purpose, currency, and positive foreign amount.": "請輸入用途、幣別與正的原幣金額。", "Enter a valid NTD amount and rate for an exchange.": "請輸入有效的新台幣金額與匯率。", "Use a negative foreign amount for investments, spending, or exchanging foreign currency back to NTD. Leave NTD and rate blank for non-exchange transactions.": "投資、支出或換回新台幣時，原幣金額請填負值；非換匯交易的新台幣與匯率請留空。", "Enter a purpose, currency, and non-zero foreign amount.": "請輸入用途、幣別與非零的原幣金額。", "Enter both NTD amount and rate, or leave both blank.": "請同時輸入新台幣金額與匯率，或兩者都留空。", "NTD amount and rate must be greater than zero.": "新台幣金額與匯率必須大於零。",
        "ETF": "ETF", "Settings": "設定", "Help": "說明", "Add": "新增",
        "No recurring investments": "目前沒有定期定額", "No recurring rules": "目前沒有定期定額規則", "Add a rule to plan your recurring investments.": "新增規則以規劃定期定額投資。",
        "No market prices": "尚無市場價格", "NTD converted": "已換算新台幣", "holdings": "筆持股", "shares": "股", "purchases": "筆投資", "monthly": "每月", "day": "日", "currency": "幣別", "currencies": "種幣別", "No foreign-currency balances recorded.": "目前沒有外幣餘額。", "No foreign-currency transactions recorded.": "目前沒有外幣交易紀錄。", "MARKET VALUE": "目前市值",
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
        "Income": "收入", "Expenses": "支出", "Savings": "儲蓄", "Salary": "薪資",
        "Bonus": "獎金", "Side Income": "副業收入", "Base Salary": "本薪", "Overtime": "加班費",
        "Freelance": "接案收入", "Necessary": "必要開銷", "Credit Card": "信用卡", "Daily Expenses": "日常花費",
        "Student Loan": "學貸", "Rent": "房租", "Utilities": "水電瓦斯網路", "Living Expenses": "生活費",
        "Principal": "本金", "Interest": "利息", "Apartment": "房租", "Electricity": "電費",
        "Internet": "網路費", "Food": "餐費", "Transportation": "交通費", "Investment": "投資金",
        "Emergency Fund": "緊急預備金", "Cash Reserve": "現金預留", "Stocks": "股票", "Monthly Reserve": "每月預留",
        "ETFs": "ETF", "High-yield Savings": "高利活存", "TOTAL P&L": "總損益", "TODAY": "今日", "vs previous close": "相較前一日收盤",
        "INVESTED": "投入成本", "HOLDINGS": "持有資產", "SYMBOL": "標的", "LAST": "現價",
        "CHANGE": "變化", "VALUE": "市值", "P&L": "損益", "ALLOCATION": "資產配置",
        "ASSETS": "資產", "ETFs 57%": "ETF 57%", "Stocks 43%": "股票 43%",
        "Display": "顯示", "Show detail percentage changes": "顯示明細百分比變化", "Performance colors": "漲跌顏色", "Green up / red down": "綠漲紅跌", "Red up / green down": "紅漲綠跌", "Analog mode": "類比模式", "Daily snapshot time": "每日快照時間", "Appearance": "外觀", "System": "跟隨系統", "Light": "淺色", "Dark": "深色", "Total Income": "總收入", "Total Expenses": "總支出", "Monthly Profit": "月結餘", "Account Allocation": "帳戶配置", "Account allocation will appear after leaf items are added.": "新增明細項目後，這裡會顯示帳戶配置。", "No items yet. Click + to add one.": "目前沒有項目，請按＋新增。", "Add child": "新增子項目", "Edit": "編輯", "Delete": "刪除", "Add item": "新增項目", "Edit item": "編輯項目", "Item name": "項目名稱", "Destination account (optional)": "轉入帳戶（選填）", "Use existing account": "使用既有帳戶", "No linked account": "不連結帳戶", "Leaf items can share a destination account. Parent items with children are totaled from their children.": "最底層項目可共用轉入帳戶；有子項目的父項目會依子項目加總。",
        "Turn this off to hide month-over-month percentages in asset and liability details.": "關閉後，資產與負債明細將隱藏月增減百分比。",
        "Language": "語言", "English": "英文", "Traditional Chinese": "繁體中文", "Total": "合計",
        "Add Asset": "新增資產", "Asset name": "資產名稱", "Asset Name": "資產名稱",
        "Category": "分類", "Asset group": "資產大分類", "Subcategory": "子分類", "Currency": "幣別", "Amount (NTD)": "金額（新台幣）",
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
    @State private var selectedPage = "Overview"
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
                .navigationSplitViewColumnWidth(240)
        } detail: {
            ZStack(alignment: .topTrailing) {
                DashboardContentView(
                    pageTitle: selectedPage,
                    selectedPage: $selectedPage,
                    appearanceMode: $activeAppearanceMode
                )
                Button {
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
            .background(FinTrackTheme.appBackground.ignoresSafeArea())
        }
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
    @Binding var selectedPage: String
    @Binding var appearanceMode: String
    @EnvironmentObject private var appModel: AppModel
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    @AppStorage("showDetailChanges") private var showDetailChanges = false
    @AppStorage("showDetailChangesInitialized") private var showDetailChangesInitialized = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.text(pageTitle, language: appLanguage))
                .font(.largeTitle.weight(.bold))
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 16)

            if pageTitle == "Portfolio" {
                PortfolioView()
            } else if pageTitle == "Dividends" {
                DividendManagementView()
            } else if pageTitle == "Recurring Investment" {
                RecurringInvestmentView(selectedPage: $selectedPage)
            } else if pageTitle == "Foreign Currency" {
                ForeignCurrencyView()
            } else if let recurring = appModel.recurringRecords.first(where: { $0.securityName == pageTitle }) {
                RecurringHoldingDetailView(rule: recurring)
            } else if pageTitle == "Income Statement" {
                IncomeStatementView()
            } else if pageTitle == "Settings" {
                ScrollView {
                    SettingsCard(showDetailChanges: $showDetailChanges, appearanceMode: $appearanceMode)
                        .padding(24)
                }
            } else if pageTitle == "Help" {
                HelpView()
            } else {
                OverviewView(showChanges: showDetailChanges)
            }
        }
        .background(FinTrackTheme.appBackground)
        .onAppear {
            if !showDetailChangesInitialized {
                showDetailChanges = false
                showDetailChangesInitialized = true
            }
        }
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

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
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

                Rectangle()
                    .fill(FinTrackTheme.divider)
                    .frame(height: 1)
                    .padding(.vertical, 4)

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
                                Text(summary.currency)
                                    .font(.headline)
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
                            .padding(.vertical, 14)
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

            HStack(spacing: 16) {
                Text(L10n.text("PURPOSE", language: appLanguage)).frame(maxWidth: .infinity, alignment: .leading)
                Text(L10n.text("CURRENCY", language: appLanguage)).frame(width: 70, alignment: .leading)
                Text(L10n.text("FOREIGN AMOUNT", language: appLanguage)).frame(width: 120, alignment: .trailing)
                Text(L10n.text("NTD", language: appLanguage)).frame(width: 90, alignment: .trailing)
                Text(L10n.text("RATE", language: appLanguage)).frame(width: 95, alignment: .trailing)
                Text(L10n.text("DATE", language: appLanguage)).frame(width: 95, alignment: .trailing)
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
                    HStack(spacing: 16) {
                        Text(transaction.purpose).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        Text(transaction.currency).frame(width: 70, alignment: .leading)
                        Text(money(transaction.foreignAmount, currency: transaction.currency))
                            .foregroundStyle(transaction.foreignAmount < 0 ? FinTrackTheme.negative : FinTrackTheme.textPrimary)
                            .frame(width: 120, alignment: .trailing)
                        Text(transaction.ntdAmount.map(ntd) ?? "—")
                            .frame(width: 90, alignment: .trailing)
                        Text(transaction.rate.map { String(format: "NTD %.4f", $0) } ?? "—")
                            .frame(width: 95, alignment: .trailing)
                        Text(transaction.tradeDate)
                            .frame(width: 95, alignment: .trailing)
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 14)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Foreign Currency")
                .font(.title2.weight(.bold))
            TextField("Currency code (e.g. EUR)", text: $currency)
                .textFieldStyle(.roundedBorder)
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
                MetricCard(title: "Total Assets", value: ntd(appModel.assetTotals.total), change: "0.0% vs last month")
                MetricCard(title: "Total Liabilities", value: ntd(appModel.liabilityTotals.total), change: "0.0% vs last month")
                MetricCard(title: "Net Worth", value: ntd(appModel.assetTotals.total - appModel.liabilityTotals.total), change: "0.0% vs last month")
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

                    ChartPlaceholder(title: "Net Worth History")
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
            DetailSection(title: "Liquid Assets", value: ntd(appModel.assetTotals.liquidAsset), change: "0.0%", children: children(for: "liquid_asset")),
            DetailSection(title: "Liquid Investments", value: ntd(appModel.assetTotals.liquidInvestment), change: "0.0%", children: children(for: "liquid_investment")),
            DetailSection(title: "Long-term Investment", value: ntd(appModel.assetTotals.longTermInvestment), change: "0.0%", children: children(for: "long_term_investment")),
            DetailSection(title: "Other Assets", value: ntd(appModel.assetTotals.otherAsset), change: "0.0%", children: children(for: "other_asset"))
        ]
    }

    private var liabilitySections: [DetailSection] {
        [
            DetailSection(title: "Short-term Liabilities", value: ntd(appModel.liabilityTotals.shortTerm), change: "0.0%", children: liabilityChildren(for: "short_term")),
            DetailSection(title: "Long-term Liabilities", value: ntd(appModel.liabilityTotals.longTerm), change: "0.0%", children: liabilityChildren(for: "long_term")),
            DetailSection(title: "Total Liabilities", value: ntd(appModel.liabilityTotals.total), change: "0.0%")
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
                    change: "0.0%",
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
                    change: "0.0%",
                    onDelete: { appModel.deleteLiability(id: liability.id) },
                    onEdit: { editingLiability = liability }
                )
            }
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

private func shares(_ value: Double, market: String) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    let isTaiwan = market.caseInsensitiveCompare("Taiwan") == .orderedSame
        || market.caseInsensitiveCompare("TW") == .orderedSame
    formatter.minimumFractionDigits = isTaiwan ? 0 : 2
    formatter.maximumFractionDigits = isTaiwan ? 0 : 2
    return formatter.string(from: NSNumber(value: value)) ?? (isTaiwan ? "0" : "0.00")
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

            TextField(L10n.text("Category", language: appLanguage), text: $category)
                .textFieldStyle(.roundedBorder)

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

    private let groups = ["Short-term Liability", "Long-term Liability"]
    private let currencies = ["NTD", "USD", "JPY"]

    init(liability: DatabaseManager.LiabilityRecord) {
        self.liability = liability
        _name = State(initialValue: liability.name)
        _group = State(initialValue: liability.liabilityGroup == "short_term" ? "Short-term Liability" : "Long-term Liability")
        _category = State(initialValue: liability.category)
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
            TextField("Category", text: $category).textFieldStyle(.roundedBorder)
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
    @State private var market = "TW"
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
        Array(Set(appModel.assets
            .filter { $0.assetGroup == assetGroup }
            .map(\.name)))
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
            if availableSubcategories.isEmpty {
                Text("Create a subcategory from Overview first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Subcategory", selection: $subcategory) {
                    ForEach(availableSubcategories, id: \.self) { category in
                        Text(category).tag(category)
                    }
                }
                .pickerStyle(.menu)
            }

            Picker("Market", selection: $market) {
                Text("Taiwan").tag("TW")
                Text("United States").tag("US")
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
                symbolSuggestions = await appModel.searchMarketSymbols(query: newValue)
            }
        }
        .onChange(of: market) { _, _ in
            Task {
                symbolSuggestions = await appModel.searchMarketSymbols(query: symbol)
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
                market: market,
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
    @State private var market: String
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
        _market = State(initialValue: holding.market)
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
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            Picker("Market", selection: $market) {
                Text("Taiwan").tag("TW")
                Text("United States").tag("US")
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
            Task { suggestions = await appModel.searchMarketSymbols(query: newValue) }
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
                market: market,
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
                    value: appModel.todayPLNTD.map(signedNTD) ?? "—",
                    detail: appModel.todayPLNTD == nil
                        ? L10n.text("No market prices", language: appLanguage)
                        : L10n.text("vs previous close", language: appLanguage),
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
        let price = holding.marketPrice.map { money($0, currency: holding.currency) } ?? "—"
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
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(dividend.securityName).font(.headline)
                                        Text(dividend.symbol).font(.caption).foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(dividend.payDate).frame(width: 130, alignment: .trailing)
                                    Text(money(dividend.amount, currency: dividend.currency))
                                        .frame(width: 140, alignment: .trailing)
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

struct HelpView: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("Help", language: appLanguage))
                .font(.title2.weight(.semibold))
            Text(L10n.text("Use the sidebar to switch between your financial sections. Market prices and exchange rates are refreshed when the relevant page is opened.", language: appLanguage))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
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
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
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
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 11)
                            }
                        }
                    }
                }
                .frame(maxHeight: 420)
            }
            .background(FinTrackTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(FinTrackTheme.border))
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .onAppear { purchases = appModel.recurringPurchases(holdingID: rule.holdingID) }
        .sheet(isPresented: $showingAddPurchase) {
            AddRecurringPurchaseSheet(rule: rule) {
                purchases = appModel.recurringPurchases(holdingID: rule.holdingID)
            }
        }
        .sheet(item: $editingSchedule) { schedule in
            EditRecurringRuleSheet(schedule: schedule)
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
    @State private var tradeDate = Date()
    @State private var shares = ""
    @State private var amount = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Record Purchase").font(.title2.weight(.bold))
            Text(rule.securityName).foregroundStyle(.secondary)
            DatePicker("Purchase date", selection: $tradeDate, displayedComponents: .date)
            TextField("Shares", text: $shares).textFieldStyle(.roundedBorder)
            TextField("Amount (\(rule.currency))", text: $amount).textFieldStyle(.roundedBorder)
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
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        do {
            try appModel.addRecurringPurchase(
                holdingID: rule.holdingID,
                tradeDate: formatter.string(from: tradeDate),
                shares: shareValue,
                amount: amountValue,
                currency: rule.currency
            )
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
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
