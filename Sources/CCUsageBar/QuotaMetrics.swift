import Foundation

/// The rolling windows the usage API reports. Lengths are fixed by the plan,
/// which is what lets us place a "time elapsed" marker on each track.
enum QuotaWindowKind {
    case fiveHour
    case sevenDay

    var length: TimeInterval {
        switch self {
        case .fiveHour: return 5 * 60 * 60
        case .sevenDay: return 7 * 24 * 60 * 60
        }
    }

    var title: String {
        switch self {
        case .fiveHour: return "5-hour limit"
        case .sevenDay: return "7-day limit"
        }
    }
}

/// Fraction (0…1) of the reset window that has already elapsed, or `nil` when it
/// can't be known honestly — no reset time, or a reset that falls outside a
/// single window. In those cases the UI shows no marker rather than guess.
func windowElapsedFraction(resetsAt: Date?,
                           length: TimeInterval,
                           now: Date = Date()) -> Double? {
    guard let resetsAt else { return nil }
    let remaining = resetsAt.timeIntervalSince(now)
    guard remaining > 0, remaining <= length else { return nil }
    return (length - remaining) / length
}
