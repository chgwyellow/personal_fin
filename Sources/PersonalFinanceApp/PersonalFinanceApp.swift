import SwiftUI

@main
struct PersonalFinanceApp: App {
    var body: some Scene {
        WindowGroup("Personal Finance") {
            DashboardView()
        }
        .windowResizability(.contentSize)
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
    }
}

struct SidebarView: View {
    @Binding var selectedPage: String
    @State private var recurringExpanded = false
    @State private var currencyExpanded = false

    var body: some View {
        List(selection: $selectedPage) {
            Section {
                page("Overview", systemImage: "square.grid.2x2")
                page("Income Statement", systemImage: "chart.line.uptrend.xyaxis")
                page("Portfolio", systemImage: "chart.pie")

                expandablePage("Recurring Investment", systemImage: "arrow.triangle.2.circlepath", isExpanded: $recurringExpanded)
                if recurringExpanded {
                    page("Stock", systemImage: "building.columns")
                    page("ETF", systemImage: "chart.bar.xaxis")
                }

                expandablePage("Foreign Currency", systemImage: "globe", isExpanded: $currencyExpanded)
                if currencyExpanded {
                    page("USD", systemImage: "dollarsign.circle")
                    page("JPY", systemImage: "yensign.circle")
                }
            }

            Section {
                page("Settings", systemImage: "gearshape")
                page("Help", systemImage: "questionmark.circle")
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            HStack(spacing: 10) {
                Image(systemName: "chart.pie.fill")
                    .foregroundStyle(.tint)
                Text("Personal Finance")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private func page(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .tag(title)
    }

    private func expandablePage(
        _ title: String,
        systemImage: String,
        isExpanded: Binding<Bool>
    ) -> some View {
        Button {
            isExpanded.wrappedValue.toggle()
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }
}

struct DashboardContentView: View {
    let pageTitle: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(pageTitle)
                    .font(.largeTitle.weight(.bold))

                HStack(spacing: 16) {
                    MetricCard(title: "Total Assets", value: "NTD 1,827,568", change: "+8.4% vs last month")
                    MetricCard(title: "Total Liabilities", value: "NTD 136,302", change: "-2.1% vs last month")
                    MetricCard(title: "Net Worth", value: "NTD 1,691,266", change: "+9.3% vs last month")
                }

                HStack(alignment: .top, spacing: 16) {
                    DetailCard(title: "Total Assets Details", rows: [
                        ("Liquid Assets", "NTD 208,839", "+3.2%"),
                        ("Liquid Investments", "NTD 1,222,362", "+10.5%"),
                        ("Other Assets", "NTD 404,004", "0.0%")
                    ])
                    DetailCard(title: "Total Liabilities Details", rows: [
                        ("Short-term Liabilities", "NTD 73,092", "-1.4%"),
                        ("Long-term Liabilities", "NTD 63,210", "-3.0%"),
                        ("Total Liabilities", "NTD 136,302", "-2.1%")
                    ])
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Net Worth History")
                        .font(.title3.weight(.semibold))
                    Text("Chart area — to be connected to snapshots")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
                .padding(20)
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let change: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.bold))
            Text(change).font(.caption).foregroundStyle(change.hasPrefix("-") ? .red : .green)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }
}

struct DetailCard: View {
    let title: String
    let rows: [(String, String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title3.weight(.semibold))
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack {
                    Text(row.0)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(row.1).fontWeight(.semibold)
                        Text(row.2).font(.caption).foregroundStyle(row.2.hasPrefix("-") ? .red : .green)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }
}
