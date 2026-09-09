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
    @Published private(set) var foreignExchangeRates: [String: Double] = [:]
    @Published private(set) var foreignExchangeRatesUpdatedAt: Date?
    private let databaseManager: DatabaseManager?
    private let marketDataClient = MarketDataClient()

    init() {
        databaseManager = try? DatabaseManager()
        refreshAssets()
        refreshLiabilities()
        refreshHoldings()
        refreshRecurringInvestments()
        refreshDividends()
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

        refreshAssets()
        refreshHoldings()
        refreshPortfolioTotals()
        refreshAllocations()
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

enum L10n {
    private static let traditionalChinese: [String: String] = [
        "Overview": "總覽", "Income Statement": "損益表", "Portfolio": "投資組合",
        "Recurring Investment": "定期定額", "Foreign Currency": "外幣", "Stock": "股票",
        "Total NTD Equivalent": "新台幣等價總額", "Currencies Held": "持有幣別", "Rates Updated": "匯率更新", "Latest Rate": "最新匯率",
        "live exchange rates": "即時匯率", "ExchangeRate-API": "ExchangeRate-API",
        "BALANCE": "餘額", "RATE": "匯率", "NTD VALUE": "新台幣等價",
        "ETF": "ETF", "Settings": "設定", "Help": "說明", "Add": "新增",
        "No recurring investments": "目前沒有定期定額",
        "No market prices": "尚無市場價格", "NTD converted": "已換算新台幣", "holdings": "筆持股", "shares": "股", "MARKET VALUE": "目前市值",
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
        "Net Worth History": "淨值歷史", "Chart area — to be connected to snapshots": "圖表區域 — 將連接資產快照",
        "Income": "收入", "Expenses": "支出", "Savings": "儲蓄", "Salary": "薪資",
        "Bonus": "獎金", "Side Income": "副業收入", "Base Salary": "本薪", "Overtime": "加班費",
        "Freelance": "接案收入", "Necessary": "必要開銷", "Credit Card": "信用卡", "Daily Expenses": "日常花費",
        "Student Loan": "學貸", "Rent": "房租", "Utilities": "水電瓦斯網路", "Living Expenses": "生活費",
        "Principal": "本金", "Interest": "利息", "Apartment": "房租", "Electricity": "電費",
        "Internet": "網路費", "Food": "餐費", "Transportation": "交通費", "Investment": "投資金",
        "Emergency Fund": "緊急預備金", "Cash Reserve": "現金預留", "Stocks": "股票", "Monthly Reserve": "每月預留",
        "ETFs": "ETF", "High-yield Savings": "高利活存", "TOTAL P&L": "總損益", "TODAY": "今日",
        "INVESTED": "投入成本", "HOLDINGS": "持有資產", "SYMBOL": "標的", "LAST": "現價",
        "CHANGE": "變化", "VALUE": "市值", "P&L": "損益", "ALLOCATION": "資產配置",
        "ASSETS": "資產", "ETFs 57%": "ETF 57%", "Stocks 43%": "股票 43%",
        "Display": "顯示", "Show detail percentage changes": "顯示明細百分比變化",
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

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedPage: $selectedPage)
                .navigationSplitViewColumnWidth(min: 220, ideal: 240)
        } detail: {
            DashboardContentView(pageTitle: selectedPage, selectedPage: $selectedPage)
        }
        .frame(minWidth: 980, minHeight: 680)
        .onAppear {
            hideWindowTitle()
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
        List(selection: $selectedPage) {
            Section {
                page("Overview", systemImage: "square.grid.2x2")
                page("Income Statement", systemImage: "chart.line.uptrend.xyaxis")
                page("Portfolio", systemImage: "chart.pie")
                page("Dividends", systemImage: "banknote")

                expandablePage("Recurring Investment", systemImage: "calendar.badge.clock", isExpanded: $recurringExpanded)
                if recurringExpanded {
                    if appModel.recurringRecords.isEmpty {
                        Text(L10n.text("No recurring investments", language: appLanguage))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 22)
                    } else {
                        ForEach(appModel.recurringRecords) { recurring in
                            page(recurring.securityName, systemImage: "chart.bar.xaxis", isChild: true)
                        }
                    }
                }

                page("Foreign Currency", systemImage: "globe.americas.fill")
            }

        }
        .listStyle(.sidebar)
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
                SidebarIconButton(systemImage: "gearshape", isSelected: selectedPage == "Settings") {
                    selectedPage = "Settings"
                }
                SidebarIconButton(systemImage: "questionmark.circle", isSelected: selectedPage == "Help") {
                    selectedPage = "Help"
                }
                Spacer()
                SidebarIconButton(systemImage: "power", isSelected: false) {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: [.command])
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.bar)
        }
    }

    private func page(
        _ title: String,
        systemImage: String,
        isChild: Bool = false
    ) -> some View {
        Label(L10n.text(title, language: appLanguage), systemImage: systemImage)
            .tag(title)
            .padding(.leading, isChild ? 22 : 0)
    }

    private func expandablePage(
        _ title: String,
        systemImage: String,
        isExpanded: Binding<Bool>
    ) -> some View {
        Button {
            selectedPage = title
            isExpanded.wrappedValue.toggle()
        } label: {
            Label(L10n.text(title, language: appLanguage), systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(selectedPage == title ? .white : .primary)
                .padding(.vertical, 7)
                .background(
                    selectedPage == title ? Color.accentColor : Color.clear,
                    in: RoundedRectangle(cornerRadius: 9)
                )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
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
                .foregroundStyle(isSelected ? .white : .primary)
                .background(
                    isSelected ? Color.accentColor : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
        }
        .buttonStyle(.plain)
    }
}

struct DashboardContentView: View {
    let pageTitle: String
    @Binding var selectedPage: String
    @EnvironmentObject private var appModel: AppModel
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    @AppStorage("showDetailChanges") private var showDetailChanges = true

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
                    SettingsCard(showDetailChanges: $showDetailChanges)
                        .padding(24)
                }
            } else {
                OverviewView(showChanges: showDetailChanges)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct ForeignCurrencyView: View {
    @EnvironmentObject private var appModel: AppModel
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    @State private var showingAdd = false
    @State private var editingAsset: DatabaseManager.AssetRecord?
    @State private var pendingDelete: ForeignCurrencySummary?

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
        .sorted { $0.currency < $1.currency }
    }

    private var lastUpdatedText: String {
        guard let date = appModel.foreignExchangeRatesUpdatedAt else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: appLanguage == AppLanguage.traditionalChinese.rawValue ? "zh_TW" : "en_US")
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var latestRateText: String {
        guard let summary = summaries.first(where: { $0.rate != nil }), let rate = summary.rate else { return "—" }
        return "NTD " + String(format: "%.4f", rate)
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
                        detail: "converted from foreign-currency balances",
                        tint: .primary,
                        height: 100
                    )
                    PortfolioMetricCard(
                        title: "Currencies Held",
                        value: "\(currencyCount)",
                        detail: currencyCount == 1 ? "currency" : "currencies",
                        tint: .primary,
                        height: 100
                    )
                    PortfolioMetricCard(
                        title: "Latest Rate",
                        value: latestRateText,
                        detail: lastUpdatedText == "—" ? "live exchange rates" : "updated \(lastUpdatedText)",
                        tint: .primary,
                        height: 100
                    )
                }

                Rectangle()
                    .fill(Color.secondary.opacity(0.28))
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
                        Text("CURRENCY").frame(maxWidth: .infinity, alignment: .leading)
                        Text(L10n.text("BALANCE", language: appLanguage)).frame(width: 150, alignment: .trailing)
                        Text(L10n.text("RATE", language: appLanguage)).frame(width: 150, alignment: .trailing)
                        Text(L10n.text("NTD VALUE", language: appLanguage)).frame(width: 170, alignment: .trailing)
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 40)
                    .padding(.top, 8)
                    .padding(.bottom, 10)

                    if summaries.isEmpty {
                        Text("No foreign-currency balances recorded.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 180)
                    } else {
                        ForEach(summaries) { summary in
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
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
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
    }
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
                .foregroundStyle(.secondary)

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
                .fill(Color.secondary.opacity(0.28))
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

private func signedNTD(_ value: Double) -> String {
    return value < 0 ? "-\(ntd(abs(value)))" : ntd(value)
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
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                Text(L10n.text("Only exchange or opening-fund cost is included. Dividends and investment gains are recorded separately.", language: appLanguage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    tint: portfolioTotals.totalPLNTD >= 0 ? .green : .red
                )
                PortfolioMetricCard(
                    title: "TODAY",
                    value: "—",
                    detail: L10n.text("No market prices", language: appLanguage),
                    tint: .primary
                )
                PortfolioMetricCard(
                    title: "MARKET VALUE",
                    value: portfolioTotals.pricedHoldings > 0 ? ntd(portfolioTotals.marketValueNTD) : "—",
                    detail: "\(displayedHoldings.count) \(L10n.text("holdings", language: appLanguage))",
                    tint: .primary
                )
            }
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
        let value = holding.marketValue.map { money($0, currency: holding.currency) } ?? "—"
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

struct PortfolioMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color
    let height: CGFloat
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue

    init(title: String, value: String, detail: String, tint: Color, height: CGFloat = 132) {
        self.title = title
        self.value = value
        self.detail = detail
        self.tint = tint
        self.height = height
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text(title, language: appLanguage)).font(.caption.weight(.bold)).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.bold)).foregroundStyle(tint)
            Text(detail).font(.caption).foregroundStyle(tint == .primary ? .secondary : tint)
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
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
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text(L10n.text("VALUE", language: appLanguage))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text(L10n.text("P&L", language: appLanguage))
                    .frame(maxWidth: .infinity, alignment: .trailing)
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
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }

    private func positionRow(_ holding: PortfolioHolding) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(holding.securityName).font(.headline).lineLimit(1)
                    Text("\(holding.quantity) \(L10n.text("shares", language: appLanguage)) · \(holding.symbol)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(holding.price).font(.headline)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(holding.value).font(.headline)
                .frame(maxWidth: .infinity, alignment: .trailing)
            VStack(alignment: .trailing, spacing: 3) {
                Text(holding.totalPL).font(.headline).foregroundStyle(holding.isNegative ? .red : .green)
                Text(holding.totalRate).font(.caption).foregroundStyle(holding.isNegative ? .red : .green)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.secondary.opacity(0.15)).frame(height: 1) }
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
                    Text("SECURITY").frame(maxWidth: .infinity, alignment: .leading)
                    Text("DATE").frame(width: 130, alignment: .trailing)
                    Text("AMOUNT").frame(width: 140, alignment: .trailing)
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
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
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
                let total = records.reduce(0) { $0 + $1.valueNTD }
                HStack(alignment: .center, spacing: 0) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.08), lineWidth: 38)
                        ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
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
                        ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
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
                        ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
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
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }

    private func allocationFraction(_ record: DatabaseManager.AllocationRecord, total: Double) -> CGFloat {
        total > 0 ? CGFloat(record.valueNTD / total) : 0
    }

    private func allocationStart(for index: Int, total: Double) -> CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(records.prefix(index).reduce(0) { $0 + $1.valueNTD } / total)
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

        for index in records.indices {
            let start = allocationStart(for: index, total: total)
            let end = start + allocationFraction(records[index], total: total)
            if position >= start && position < end { return index }
        }
        return nil
    }

    private func allocationColor(_ index: Int) -> Color {
        [
            Color(red: 0.05, green: 0.34, blue: 0.34),
            Color(red: 0.06, green: 0.24, blue: 0.42),
            Color(red: 0.30, green: 0.12, blue: 0.38),
            Color(red: 0.48, green: 0.24, blue: 0.08),
            Color(red: 0.45, green: 0.08, blue: 0.18)
        ][index % 5]
    }
}

struct LegacyAllocationCard: View {
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    private let segments = [
        AllocationSegment(name: "富邦公司治理", weight: "34.6%", value: 0.346, color: Color(red: 0.18, green: 0.60, blue: 0.53)),
        AllocationSegment(name: "兆聯實業", weight: "19.4%", value: 0.194, color: Color(red: 0.78, green: 0.60, blue: 0.34)),
        AllocationSegment(name: "VT", weight: "17.0%", value: 0.170, color: Color(red: 0.35, green: 0.48, blue: 0.68)),
        AllocationSegment(name: "NVIDIA", weight: "13.6%", value: 0.136, color: Color(red: 0.56, green: 0.42, blue: 0.62)),
        AllocationSegment(name: "BND", weight: "4.9%", value: 0.049, color: Color(red: 0.78, green: 0.45, blue: 0.36)),
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
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
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
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
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
                    .stroke(Color.blue.opacity(0.8), style: StrokeStyle(lineWidth: 42, lineCap: .butt))
                Circle()
                    .trim(from: 0, to: 0.34)
                    .stroke(Color.cyan, style: StrokeStyle(lineWidth: 42, lineCap: .butt))
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
                            .fill(bar.1 > 0.5 ? Color.green : Color.blue)
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
    .background(.background, in: RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
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
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
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
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }
}

struct IncomeStatementView: View {
    private let income = StatementSection(title: "Income", rows: [
        StatementRow(name: "Salary", value: "NTD 45,269", children: [
            StatementRow(name: "Base Salary", value: "NTD 42,000"),
            StatementRow(name: "Overtime", value: "NTD 3,269")
        ]),
        StatementRow(name: "Bonus", value: "NTD 0"),
        StatementRow(name: "Side Income", value: "NTD 2,880", children: [
            StatementRow(name: "Freelance", value: "NTD 2,880"),
            StatementRow(name: "Other", value: "NTD 0")
        ])
    ], total: "NTD 48,149")

    private let expenses = StatementSection(title: "Expenses", rows: [
        StatementRow(name: "Student Loan", value: "NTD 4,237", children: [
            StatementRow(name: "Principal", value: "NTD 3,500"),
            StatementRow(name: "Interest", value: "NTD 737")
        ]),
        StatementRow(name: "Rent", value: "NTD 10,000", children: [
            StatementRow(name: "Apartment", value: "NTD 10,000")
        ]),
        StatementRow(name: "Utilities", value: "NTD 500", children: [
            StatementRow(name: "Electricity", value: "NTD 300"),
            StatementRow(name: "Internet", value: "NTD 200")
        ]),
        StatementRow(name: "Living Expenses", value: "NTD 6,000", children: [
            StatementRow(name: "Food", value: "NTD 4,000"),
            StatementRow(name: "Transportation", value: "NTD 2,000")
        ])
    ], total: "NTD 50,826")

    private let savings = StatementSection(title: "Savings", rows: [
        StatementRow(name: "Investment", value: "NTD 15,532", children: [
            StatementRow(name: "Stocks", value: "NTD 8,000"),
            StatementRow(name: "ETFs", value: "NTD 7,532")
        ]),
        StatementRow(name: "Emergency Fund", value: "NTD 12,855", children: [
            StatementRow(name: "High-yield Savings", value: "NTD 12,855")
        ]),
        StatementRow(name: "Cash Reserve", value: "NTD 5,000", children: [
            StatementRow(name: "Monthly Reserve", value: "NTD 5,000")
        ])
    ], total: "NTD 33,387")

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                MetricCard(title: "Total Income", value: income.total, change: "+4.2% vs last month")
                MetricCard(title: "Total Expenses", value: expenses.total, change: "-1.8% vs last month")
                MetricCard(title: "Monthly Profit", value: "NTD 0", change: "+6.1% vs last month")
            }
            .padding(.horizontal, 24)

            ScrollView {
                ViewThatFits(in: .horizontal) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 16) {
                            StatementCard(section: income)
                            StatementCard(section: expenses)
                        }
                        StatementCard(section: savings)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        StatementCard(section: income)
                        StatementCard(section: expenses)
                        StatementCard(section: savings)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
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
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
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
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue

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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }
}

struct RecurringInvestmentView: View {
    @EnvironmentObject private var appModel: AppModel
    @Binding var selectedPage: String
    @State private var showingAddRule = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recurring Rules")
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
                    "No recurring rules",
                    systemImage: "calendar.badge.clock",
                    description: Text("Add a rule to plan your recurring investments.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(appModel.recurringRecords) { rule in
                            Button {
                                selectedPage = rule.securityName
                            } label: {
                                recurringRuleRow(rule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(.background, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
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
                Text("\(rule.symbol) · " + rule.schedules.map { "\($0.frequency) day \($0.executionDay)" }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(money(rule.plannedAmount, currency: rule.currency)).font(.headline)
                Text("Click to view purchases").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

struct RecurringHoldingDetailView: View {
    let rule: DatabaseManager.RecurringRecord
    @EnvironmentObject private var appModel: AppModel
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
                    detail: "\(purchases.count) purchases",
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
                    detail: rule.frequency,
                    tint: .primary
                )
            }

            Rectangle()
                .fill(Color.secondary.opacity(0.28))
                .frame(height: 1)
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text("SCHEDULES").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                ForEach(rule.schedules) { schedule in
                    HStack {
                        Text("\(money(schedule.plannedAmount, currency: schedule.currency)) · \(schedule.frequency) · day \(schedule.executionDay)")
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
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))

            VStack(spacing: 0) {
                HStack {
                    Text("PURCHASES").font(.caption.weight(.bold)).foregroundStyle(.secondary)
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
                    Text("DATE").frame(maxWidth: .infinity, alignment: .leading)
                    Text("SHARES").frame(width: 120, alignment: .trailing)
                    Text("AMOUNT").frame(width: 140, alignment: .trailing)
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        if purchases.isEmpty {
                            Text("No purchases recorded. Click + to add the actual transaction.")
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
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
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
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text(title, language: appLanguage)).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.bold))
            Text(change.replacingOccurrences(of: " vs last month", with: appLanguage == AppLanguage.traditionalChinese.rawValue ? " 較上月" : " vs last month"))
                .font(.caption).foregroundStyle(change.hasPrefix("-") ? .red : .green)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
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
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }

    private func detailRow(name: String, value: String, change: String, showChange: Bool) -> some View {
        HStack(alignment: .top) {
            Text(L10n.text(name, language: appLanguage))
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(value)
                if showChange {
                    Text(change)
                        .font(.caption)
                        .foregroundStyle(change.hasPrefix("-") ? .red : .green)
                }
            }
        }
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
