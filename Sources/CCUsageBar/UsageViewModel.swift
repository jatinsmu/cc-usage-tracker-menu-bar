import SwiftUI

// MARK: - App state

enum AppState {
    case loading
    case noCredentials
    case tokenExpired
    case unauthorized
    case offline(UsageSnapshot?)   // network error; last known snapshot preserved if available
    case live(UsageSnapshot)
}

// MARK: - ViewModel

@MainActor
final class UsageViewModel: ObservableObject {
    @Published var state: AppState = .loading
    @Published var lastErrorMessage: String?

    private let pollInterval: UInt64 = 900_000_000_000  // 15 min in nanoseconds
    private var nextPollDelay: UInt64? = nil            // override for rate-limit backoff
    private var pollTask: Task<Void, Never>?

    init() { startPolling() }

    deinit { pollTask?.cancel() }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.poll()
                let delay = self.nextPollDelay ?? self.pollInterval
                self.nextPollDelay = nil
                try? await Task.sleep(nanoseconds: delay)
            }
        }
    }

    func refresh() {
        Task { await poll() }
    }

    // MARK: - Core poll

    private func poll() async {
        do {
            // Read Keychain off the main actor: SecItemCopyMatching is synchronous
            // and blocks until any ACL dialog is dismissed.
            let creds = try await Task.detached(priority: .userInitiated) {
                try KeychainReader.readCredentials()
            }.value

            if let exp = creds.expiresAt, exp < Date() {
                state = .tokenExpired
                return
            }

            let snapshot = try await UsageClient.fetch(token: creds.accessToken)
            state = .live(snapshot)
            lastErrorMessage = nil

        } catch KeychainError.itemNotFound {
            state = .noCredentials

        } catch let e as KeychainError {
            // Any other keychain failure (ACL denied, parse error, etc.) —
            // show it separately rather than folding into generic "offline"
            state = .offline(nil)
            lastErrorMessage = e.localizedDescription

        } catch UsageClientError.unauthorized {
            state = .unauthorized

        } catch UsageClientError.rateLimited(let retryAfter) {
            // Keep last-known snapshot visible; schedule backoff
            let last: UsageSnapshot? = {
                switch self.state {
                case .live(let s), .offline(let s?): return s
                default: return nil
                }
            }()
            state = .offline(last)
            // Honour Retry-After if present, otherwise wait the normal 15 min
            if let after = retryAfter {
                nextPollDelay = UInt64(after * 1_000_000_000)
            }
            lastErrorMessage = "Rate limited (429) — next auto-refresh in \(Int((retryAfter ?? 900) / 60)) min"

        } catch {
            // Network or other error — preserve last-known snapshot for dimmed display
            let last: UsageSnapshot? = {
                switch self.state {
                case .live(let s), .offline(let s?): return s
                default: return nil
                }
            }()
            state = .offline(last)
            lastErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Menu bar label / symbol

    var menuBarLabel: String {
        switch state {
        case .loading:            return "--"
        case .noCredentials:      return "?"
        case .tokenExpired,
             .unauthorized:       return "!"
        case .offline(nil):       return "--"
        case .live(let s),
             .offline(.some(let s)):
            switch s.displayMode {
            case .percent:
                return "\(Int((s.fiveHour?.utilization ?? 0).rounded()))%"
            case .dollar:
                guard let used = s.spend?.used else { return "$?" }
                return String(format: "$%.2f", used.dollars)
            }
        }
    }

    var menuBarSymbol: String {
        switch state {
        case .loading, .noCredentials: return "gauge"
        case .tokenExpired, .unauthorized: return "exclamationmark.triangle.fill"
        case .offline:                 return "gauge.with.dots.needle.33percent"
        case .live(let s):             return s.activeSeverity.symbolName
        }
    }

    var isOffline: Bool {
        if case .offline = state { return true }
        return false
    }

    // Snapshot to display (nil when no data at all)
    var currentSnapshot: UsageSnapshot? {
        switch state {
        case .live(let s), .offline(.some(let s)): return s
        default: return nil
        }
    }
}
