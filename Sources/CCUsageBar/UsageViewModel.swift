import SwiftUI
import AppKit

// MARK: - App state

enum AppState {
    case loading
    case noCredentials
    case tokenExpired
    case unauthorized
    case offline(UsageSnapshot?)   // network error; last known snapshot preserved if available
    case live(UsageSnapshot)
}

// MARK: - Update availability
//
// Kept separate from `AppState` on purpose: an available update is orthogonal to
// the usage display (it should show in any state) and shouldn't force a new case
// through the menu-bar label/symbol/popover switch.
enum UpdateAvailability: Equatable {
    case unknown
    case upToDate
    case available(ReleaseInfo)
}

// MARK: - ViewModel

@MainActor
final class UsageViewModel: ObservableObject {
    @Published var state: AppState = .loading
    @Published var lastErrorMessage: String?
    @Published var update: UpdateAvailability = .unknown

    private let pollInterval: UInt64 = 900_000_000_000  // 15 min in nanoseconds
    private var nextPollDelay: UInt64? = nil            // override for rate-limit backoff
    private var pollTask: Task<Void, Never>?

    // Throttle update checks to at most once per day; persisted across launches.
    private let updateCheckInterval: TimeInterval = 24 * 60 * 60
    private let lastUpdateCheckKey = "CCUsageBar.lastUpdateCheck"

    /// - Parameter autoStart: begin the 15-minute poll loop immediately.
    ///   Tests pass `false` to build a view model with no network/Keychain
    ///   side effects, then drive `state` directly.
    init(autoStart: Bool = true) {
        if autoStart {
            startPolling()
            Task { await checkForUpdateIfDue() }
        }
    }

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

    // MARK: - Update check

    /// Check GitHub for a newer release if a day has passed since the last check.
    /// Any failure is swallowed to "no update known" — the updater must never
    /// disrupt the usage display.
    func checkForUpdateIfDue(force: Bool = false) async {
        let defaults = UserDefaults.standard
        if !force {
            let last = defaults.double(forKey: lastUpdateCheckKey)
            if last > 0, Date().timeIntervalSince1970 - last < updateCheckInterval { return }
        }
        defaults.set(Date().timeIntervalSince1970, forKey: lastUpdateCheckKey)

        guard let latest = try? await UpdateChecker.checkLatest() else { return }
        if UpdateChecker.isNewer(latest.version, than: UpdateChecker.currentVersion) {
            update = .available(latest)
        } else {
            update = .upToDate
        }
    }

    /// Download the available release's asset and reveal it in Finder for the
    /// user to install manually (no Developer ID → no safe silent swap).
    func downloadUpdate() {
        guard case .available(let release) = update else { return }
        guard let asset = release.assetURL else {
            lastErrorMessage = UpdateError.noAsset.localizedDescription
            // Fall back to opening the release page so the user isn't stuck.
            NSWorkspace.shared.open(release.pageURL)
            return
        }
        Task {
            do {
                let saved = try await UpdateChecker.download(asset)
                NSWorkspace.shared.activateFileViewerSelecting([saved])
            } catch {
                lastErrorMessage = error.localizedDescription
                NSWorkspace.shared.open(release.pageURL)
            }
        }
    }

    var availableUpdate: ReleaseInfo? {
        if case .available(let r) = update { return r }
        return nil
    }

    // MARK: - Core poll

    private func poll() async {
        do {
            // Read Keychain off the main actor: SecItemCopyMatching is synchronous
            // and blocks until any ACL dialog is dismissed.
            let creds = try await Task.detached(priority: .userInitiated) {
                try await KeychainReader.readCredentials()
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
            return "\(Int((s.fiveHour?.utilization ?? 0).rounded()))%"
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
