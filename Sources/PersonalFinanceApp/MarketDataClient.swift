import Foundation

/// Searches public market metadata without storing the whole market universe locally.
struct MarketDataClient {
    struct SearchResult: Identifiable, Decodable {
        let symbol: String
        let shortname: String?
        let longname: String?
        let quoteType: String?

        var id: String { symbol }
        var displayName: String { longname ?? shortname ?? symbol }
    }

    private struct SearchResponse: Decodable {
        let quotes: [SearchResult]
    }

    struct Quote {
        let price: Double
        let currency: String
        let previousClose: Double?
    }

    private struct ChartResponse: Decodable {
        let chart: Chart
        struct Chart: Decodable {
            let result: [Result]?
        }
        struct Result: Decodable {
            let meta: Meta
        }
        struct Meta: Decodable {
            let regularMarketPrice: Double?
            let currency: String?
            let regularMarketPreviousClose: Double?
            let previousClose: Double?
        }
    }

    private struct ExchangeResponse: Decodable {
        let rates: [String: Double]
    }

    enum ClientError: LocalizedError {
        case invalidResponse

        var errorDescription: String? {
            "Unable to search market symbols."
        }
    }

    /// Searches Yahoo Finance metadata and returns a small transient result set.
    func searchSymbols(query: String) async throws -> [SearchResult] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var components = URLComponents(string: "https://query1.finance.yahoo.com/v1/finance/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components?.url else { throw ClientError.invalidResponse }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw ClientError.invalidResponse
        }

        return try JSONDecoder().decode(SearchResponse.self, from: data).quotes
            .filter { $0.quoteType == "EQUITY" || $0.quoteType == "ETF" }
            .prefix(8)
            .map { $0 }
    }

    /// Fetches one current quote for a selected symbol.
    func fetchQuote(symbol: String) async throws -> Quote? {
        let escapedSymbol = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(escapedSymbol)?range=5d&interval=1d") else {
            throw ClientError.invalidResponse
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw ClientError.invalidResponse
        }
        let decoded = try JSONDecoder().decode(ChartResponse.self, from: data)
        guard let meta = decoded.chart.result?.first?.meta,
              let price = meta.regularMarketPrice else { return nil }
        return Quote(
            price: price,
            currency: meta.currency ?? "USD",
            previousClose: meta.regularMarketPreviousClose ?? meta.previousClose
        )
    }

    /// Fetches one exchange rate quoted against Taiwan dollars.
    func fetchExchangeRate(baseCurrency: String) async throws -> Double? {
        guard baseCurrency != "NTD" else { return 1 }
        guard let url = URL(string: "https://open.er-api.com/v6/latest/\(baseCurrency)") else {
            throw ClientError.invalidResponse
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw ClientError.invalidResponse
        }
        return try JSONDecoder().decode(ExchangeResponse.self, from: data).rates["TWD"]
    }
}
