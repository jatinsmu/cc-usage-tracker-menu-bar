import Foundation

// MARK: - Error

enum UsageClientError: Error, LocalizedError {
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "API returned 401 — token may be expired"
        case .rateLimited(let after):
            if let s = after {
                return "Rate limited by API — retry in \(Int(s))s"
            }
            return "Rate limited by API (429)"
        case .httpError(let code):
            return "API returned HTTP \(code)"
        }
    }
}

// MARK: - Client

enum UsageClient {
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    static func fetch(token: String) async throws -> UsageSnapshot {
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20",  forHTTPHeaderField: "anthropic-beta")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard http.statusCode == 200 else {
            switch http.statusCode {
            case 401:
                throw UsageClientError.unauthorized
            case 429:
                let retryAfter = (http.value(forHTTPHeaderField: "Retry-After"))
                    .flatMap(Double.init)
                throw UsageClientError.rateLimited(retryAfter: retryAfter)
            default:
                throw UsageClientError.httpError(http.statusCode)
            }
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let c   = try d.singleValueContainer()
            let str = try c.decode(String.self)
            // Try with fractional seconds first (API returns e.g. "…17:10:00.360864+00:00")
            let withFrac = ISO8601DateFormatter()
            withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFrac.date(from: str) { return date }
            // Fall back to no fractional seconds
            let noFrac = ISO8601DateFormatter()
            noFrac.formatOptions = [.withInternetDateTime]
            if let date = noFrac.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(
                in: c, debugDescription: "Unparseable date: \(str)")
        }

        return try decoder.decode(UsageSnapshot.self, from: data)
    }
}
