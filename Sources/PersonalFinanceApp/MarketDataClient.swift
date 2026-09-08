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
}
