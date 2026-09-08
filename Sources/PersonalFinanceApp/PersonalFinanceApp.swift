import AppKit
import Foundation
import SwiftUI

@main
struct PersonalFinanceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            DashboardView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        configureWindows()
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
        "ETF": "ETF", "Settings": "設定", "Help": "說明", "Add": "新增",
        "Total Assets": "總資產", "Total Liabilities": "總負債", "Net Worth": "淨值",
        "Total Assets Details": "總資產明細", "Total Liabilities Details": "總負債明細",
        "Liquid Asset": "流動資產", "Liquid Investment": "流動性投資", "Other Asset": "其他資產",
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
        "Category": "分類", "Currency": "幣別", "Amount (NTD)": "金額（新台幣）",
        "Original amount": "原幣金額", "Initial NTD cost": "初始新台幣成本", "Average exchange rate": "平均匯率",
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
            DashboardContentView(pageTitle: selectedPage)
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
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    @State private var recurringExpanded = false
    @State private var currencyExpanded = false

    var body: some View {
        List(selection: $selectedPage) {
            Section {
                page("Overview", systemImage: "square.grid.2x2")
                page("Income Statement", systemImage: "chart.line.uptrend.xyaxis")
                page("Portfolio", systemImage: "chart.pie")

                expandablePage("Recurring Investment", systemImage: "calendar.badge.clock", isExpanded: $recurringExpanded)
                if recurringExpanded {
                    page("Stock", systemImage: "building.columns", isChild: true)
                    page("ETF", systemImage: "chart.bar.xaxis", isChild: true)
                }

                expandablePage("Foreign Currency", systemImage: "globe.americas.fill", isExpanded: $currencyExpanded)
                if currencyExpanded {
                    page("USD", systemImage: "dollarsign.circle", isChild: true)
                    page("JPY", systemImage: "yensign.circle", isChild: true)
                }
            }

        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            HStack {
                Text("FinTrack")
                    .font(.title2.weight(.bold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 14) {
                SidebarIconButton(title: "Settings", systemImage: "gearshape", isSelected: selectedPage == "Settings") {
                    selectedPage = "Settings"
                }
                SidebarIconButton(title: "Help", systemImage: "questionmark.circle", isSelected: selectedPage == "Help") {
                    selectedPage = "Help"
                }
                Spacer()
                SidebarIconButton(title: "Quit", systemImage: "power", isSelected: false) {
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
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 28, height: 28)
                .foregroundStyle(isSelected ? .white : .primary)
                .background(
                    isSelected ? Color.accentColor : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay(alignment: .trailing) {
                    if isHovering {
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                            .fixedSize()
                            .offset(x: 46)
                            .zIndex(10)
                            .allowsHitTesting(false)
                    }
                }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct DashboardContentView: View {
    let pageTitle: String
    @AppStorage("showDetailChanges") private var showDetailChanges = true
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.text(pageTitle, language: appLanguage))
                .font(.largeTitle.weight(.bold))
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 16)

            if pageTitle == "Portfolio" {
                PortfolioView()
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

struct OverviewView: View {
    let showChanges: Bool
    @State private var showingAddAsset = false
    @State private var showingAddLiability = false

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                MetricCard(title: "Total Assets", value: "NTD 1,827,568", change: "+8.4% vs last month")
                MetricCard(title: "Total Liabilities", value: "NTD 136,302", change: "-2.1% vs last month")
                MetricCard(title: "Net Worth", value: "NTD 1,691,266", change: "+9.3% vs last month")
            }
            .padding(.horizontal, 24)

            ScrollView {
                VStack(spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        DetailCard(title: "Total Assets Details", showChanges: showChanges, onAdd: {
                            showingAddAsset = true
                        }, sections: [
                            DetailSection(title: "Liquid Assets", value: "NTD 208,839", change: "+3.2%", children: [
                                DetailRow(name: "Bank Accounts", value: "NTD 76,636", change: "+1.8%"),
                                DetailRow(name: "Cash", value: "NTD 50,000", change: "0.0%"),
                                DetailRow(name: "Margin Deposit", value: "NTD 82,203", change: "+6.4%")
                            ]),
                            DetailSection(title: "Liquid Investments", value: "NTD 1,222,362", change: "+10.5%", children: [
                                DetailRow(name: "U.S. Stocks", value: "NTD 290,857", change: "+8.1%"),
                                DetailRow(name: "U.S. ETFs", value: "NTD 350,193", change: "+12.4%"),
                                DetailRow(name: "Taiwan ETFs", value: "NTD 581,312", change: "+9.7%")
                            ]),
                            DetailSection(title: "Other Assets", value: "NTD 404,004", change: "0.0%", children: [
                                DetailRow(name: "Retirement Fund", value: "NTD 376,004", change: "0.0%"),
                                DetailRow(name: "House Deposit", value: "NTD 28,000", change: "0.0%"),
                                DetailRow(name: "Other", value: "NTD 0", change: "0.0%")
                            ])
                        ])

                        VStack(spacing: 16) {
                            DetailCard(title: "Total Liabilities Details", showChanges: showChanges, onAdd: {
                                showingAddLiability = true
                            }, sections: [
                                DetailSection(title: "Short-term Liabilities", value: "NTD 73,092", change: "-1.4%", children: [
                                    DetailRow(name: "Credit Card", value: "NTD 73,092", change: "-1.4%")
                                ]),
                                DetailSection(title: "Long-term Liabilities", value: "NTD 63,210", change: "-3.0%", children: [
                                    DetailRow(name: "Student Loan", value: "NTD 63,210", change: "-3.0%")
                                ]),
                                DetailSection(title: "Total Liabilities", value: "NTD 136,302", change: "-2.1%")
                            ])
                            FinancialIndicatorsCard()
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
    }
}

struct AddAssetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var category = "Liquid Asset"
    @State private var currency = "NTD"
    @State private var amount = ""
    @State private var ntdCost = ""
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue

    private let categories = ["Liquid Asset", "Liquid Investment", "Other Asset"]
    private let currencies = ["NTD", "USD", "JPY"]

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

            Picker(L10n.text("Category", language: appLanguage), selection: $category) {
                ForEach(categories, id: \.self) { category in
                    Text(L10n.text(category, language: appLanguage)).tag(category)
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
                TextField(L10n.text("Initial NTD cost", language: appLanguage), text: $ntdCost)
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
                    // Demo only: database insertion will be connected later.
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

struct AddLiabilitySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var group = "Short-term Liability"
    @State private var category = "Credit Card"
    @State private var currency = "NTD"
    @State private var balance = ""
    @State private var interestRate = ""
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
                    // Demo only: database insertion will be connected later.
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

struct PortfolioView: View {
    private let holdings = [
        PortfolioHolding(symbol: "VT", quantity: "53.3636", average: "$110.93", price: "$161.73", capitalPL: "$2,710.97", totalPL: "$2,932.63", capitalRate: "45.80%", totalRate: "49.54%", value: "$8,630.49", cost: "$5,919.52", weight: "17.13%", totalReturn: "NT$1,010,188", fx: "31.6858"),
        PortfolioHolding(symbol: "BND", quantity: "34.8085", average: "$73.05", price: "$71.95", capitalPL: "-$38.45", totalPL: "$129.77", capitalRate: "-1.51%", totalRate: "5.10%", value: "$2,504.47", cost: "$2,542.92", weight: "4.97%", totalReturn: "", fx: ""),
        PortfolioHolding(symbol: "MONSTER", quantity: "40", average: "$25.67", price: "$43.82", capitalPL: "$726.01", totalPL: "$726.01", capitalRate: "70.71%", totalRate: "70.71%", value: "$1,752.80", cost: "$1,026.79", weight: "3.48%", totalReturn: "", fx: ""),
        PortfolioHolding(symbol: "PALANTIR", quantity: "3", average: "$26.07", price: "$174.33", capitalPL: "$444.67", totalPL: "$444.67", capitalRate: "567.76%", totalRate: "567.76%", value: "$522.99", cost: "$78.32", weight: "1.04%", totalReturn: "", fx: ""),
        PortfolioHolding(symbol: "NVIDIA", quantity: "30", average: "$25.36", price: "$230.36", capitalPL: "$6,150.03", totalPL: "$6,159.94", capitalRate: "808.40%", totalRate: "809.70%", value: "$6,910.80", cost: "$760.77", weight: "13.71%", totalReturn: "", fx: ""),
        PortfolioHolding(symbol: "VINFAST", quantity: "50", average: "$4.25", price: "$3.08", capitalPL: "-$58.82", totalPL: "-$58.82", capitalRate: "-27.64%", totalRate: "-27.64%", value: "$154.00", cost: "$212.82", weight: "0.31%", totalReturn: "", fx: ""),
        PortfolioHolding(symbol: "富邦公司治理", quantity: "5,822", average: "NT$33.39", price: "NT$94.40", capitalPL: "NT$355,192", totalPL: "NT$405,875", capitalRate: "183.05%", totalRate: "209.17%", value: "NT$549,597", cost: "NT$194,404", weight: "34.42%", totalReturn: "", fx: ""),
        PortfolioHolding(symbol: "星宇航空", quantity: "2,000", average: "NT$24.15", price: "NT$20.60", capitalPL: "-NT$7,150", totalPL: "-NT$7,150", capitalRate: "-14.79%", totalRate: "-14.79%", value: "NT$41,200", cost: "NT$48,350", weight: "2.58%", totalReturn: "", fx: ""),
        PortfolioHolding(symbol: "柏承", quantity: "1,000", average: "NT$41.25", price: "NT$49.55", capitalPL: "NT$8,280", totalPL: "NT$8,280", capitalRate: "20.06%", totalRate: "20.06%", value: "NT$49,550", cost: "NT$41,270", weight: "3.10%", totalReturn: "", fx: ""),
        PortfolioHolding(symbol: "兆聯實業", quantity: "429", average: "NT$115.40", price: "NT$717.00", capitalPL: "NT$258,085", totalPL: "NT$275,735", capitalRate: "521.30%", totalRate: "556.95%", value: "NT$307,593", cost: "NT$49,508", weight: "19.26%", totalReturn: "", fx: "")
    ]

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                PortfolioMetricCard(title: "TOTAL P&L", value: "+NT$29,548.1", detail: "+140.3% on cost", tint: .green)
                PortfolioMetricCard(title: "TODAY", value: "-NT$64.0", detail: "-0.1%", tint: .red)
                PortfolioMetricCard(title: "INVESTED", value: "NT$667,537", detail: "10 holdings", tint: .primary)
            }
            .padding(.horizontal, 24)

            ScrollView {
                VStack(spacing: 16) {
                    AllocationCard()
                    ScrollView(.horizontal) {
                        PositionsCard(holdings: holdings)
                            .frame(minWidth: 1040)
                    }
                    .scrollIndicators(.visible)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }
}

struct PortfolioMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text(title, language: appLanguage)).font(.caption.weight(.bold)).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.bold)).foregroundStyle(tint)
            Text(detail).font(.caption).foregroundStyle(tint == .primary ? .secondary : tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }
}

struct PositionsCard: View {
    let holdings: [PortfolioHolding]
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.text("HOLDINGS", language: appLanguage)).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                Spacer()
                Button(L10n.text("Add", language: appLanguage), systemImage: "plus") { }
                    .buttonStyle(.plain)
                    .font(.callout.weight(.semibold))
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            HStack(spacing: 18) {
                Text(L10n.text("SYMBOL", language: appLanguage))
                    .frame(width: 350, alignment: .leading)
                Text(L10n.text("LAST", language: appLanguage)).frame(width: 130, alignment: .trailing)
                Text(L10n.text("CHANGE", language: appLanguage)).frame(width: 130, alignment: .trailing)
                Text(L10n.text("VALUE", language: appLanguage)).frame(width: 150, alignment: .trailing)
                Text(L10n.text("P&L", language: appLanguage)).frame(width: 150, alignment: .trailing)
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(holdings) { holding in
                        positionRow(holding)
                    }
                }
            }
            .frame(maxHeight: 480)
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }

    private func positionRow(_ holding: PortfolioHolding) -> some View {
        HStack(spacing: 18) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(holding.symbol).font(.headline)
                    Text("\(holding.quantity) sh · \(holding.companyName)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(width: 350, alignment: .leading)

            Text(holding.price).font(.headline).frame(width: 130, alignment: .trailing)
            VStack(alignment: .trailing, spacing: 4) {
                Text(holding.dayChange).font(.callout.weight(.semibold))
                    .foregroundStyle(holding.isNegative ? .red : .green)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background((holding.isNegative ? Color.red : Color.green).opacity(0.12), in: Capsule())
                Text(holding.dayRate).font(.caption).foregroundStyle(holding.isNegative ? .red : .green)
            }
            .frame(width: 130, alignment: .trailing)
            Text(holding.value).font(.headline).frame(width: 150, alignment: .trailing)
            VStack(alignment: .trailing, spacing: 3) {
                Text(holding.totalPL).font(.headline).foregroundStyle(holding.isNegative ? .red : .green)
                Text(holding.totalRate).font(.caption).foregroundStyle(holding.isNegative ? .red : .green)
            }
            .frame(width: 150, alignment: .trailing)
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.secondary.opacity(0.15)).frame(height: 1) }
    }
}

struct AllocationCard: View {
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
    let id = UUID()
    let symbol: String
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

    var isNegative: Bool { totalPL.hasPrefix("-") }

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
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.english.rawValue
    private let indicators = [
        ("Free Cash Flow", "NTD 1,287,262"),
        ("Liability Ratio", "7.46%"),
        ("Cash Ratio", "153.22%"),
        ("Equity Multiplier", "1.08"),
        ("Net Worth Growth Rate", "+3.73%")
    ]

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
}
