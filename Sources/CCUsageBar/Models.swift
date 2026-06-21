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

// MARK: - Display mode

enum DisplayMode {
    case percent   // limit-based plans: spend.enabled=false
    case dollar    // usage-billed/enterprise: spend.enabled=true
}

// MARK: - API response types

struct UsageWindow: Decodable {
    let utilization: Double
    let resetsAt: Date?
    let limitDollars: Double?
    let usedDollars: Double?
    let remainingDollars: Double?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt          = "resets_at"
        case limitDollars      = "limit_dollars"
        case usedDollars       = "used_dollars"
        case remainingDollars  = "remaining_dollars"
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

struct SpendAmount: Decodable {
    let amountMinor: Int
    let currency: String

    enum CodingKeys: String, CodingKey {
        case amountMinor = "amount_minor"
        case currency
    }

    var dollars: Double { Double(amountMinor) / 100.0 }
}

struct Spend: Decodable {
    let enabled: Bool
    let used: SpendAmount?
    let limit: SpendAmount?
}

// MARK: - UsageSnapshot

struct UsageSnapshot: Decodable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    let limits: [UsageLimit]
    let spend: Spend?
    let fetchedAt: Date  // injected at decode time; not from JSON

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case limits
        case spend
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fiveHour  = try c.decodeIfPresent(UsageWindow.self, forKey: .fiveHour)
        sevenDay  = try c.decodeIfPresent(UsageWindow.self, forKey: .sevenDay)
        limits    = try c.decodeIfPresent([UsageLimit].self, forKey: .limits) ?? []
        spend     = try c.decodeIfPresent(Spend.self, forKey: .spend)
        fetchedAt = Date()
    }

    // MARK: Derived

    var displayMode: DisplayMode {
        if spend?.enabled == true { return .dollar }
        if fiveHour?.limitDollars != nil { return .dollar }
        return .percent
    }

    var activeSeverity: Severity {
        limits.first(where: { $0.isActive == true })?.severity ?? .normal
    }
}
