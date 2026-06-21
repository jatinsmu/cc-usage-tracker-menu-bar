import Foundation

// MARK: - Severity

enum Severity: String, Codable {
    case normal, warning, critical

    var symbolName: String {
        switch self {
        case .normal:   return "gauge.with.dots.needle.33percent"
        case .warning:  return "gauge.with.dots.needle.67percent"
        case .critical: return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - API response types

struct UsageWindow: Decodable {
    let utilization: Double
    let resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

struct UsageLimit: Decodable {
    let kind: String
    let group: String
    let percent: Int?
    let severity: Severity?
    let resetsAt: Date?
    let isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case kind, group, percent, severity
        case resetsAt = "resets_at"
        case isActive = "is_active"
    }
}

// MARK: - UsageSnapshot

struct UsageSnapshot: Decodable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    let limits: [UsageLimit]
    let fetchedAt: Date  // injected at decode time; not from JSON

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case limits
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fiveHour  = try c.decodeIfPresent(UsageWindow.self, forKey: .fiveHour)
        sevenDay  = try c.decodeIfPresent(UsageWindow.self, forKey: .sevenDay)
        limits    = try c.decodeIfPresent([UsageLimit].self, forKey: .limits) ?? []
        fetchedAt = Date()
    }

    // MARK: Derived

    var activeSeverity: Severity {
        limits.first(where: { $0.isActive == true })?.severity ?? .normal
    }
}
