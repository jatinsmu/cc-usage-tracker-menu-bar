import SwiftUI

struct PopoverView: View {
    @EnvironmentObject private var vm: UsageViewModel

    var body: some View {
        stateContent.frame(width: 300)
    }

    // MARK: - State router

    @ViewBuilder
    private var stateContent: some View {
        switch vm.state {
        case .loading:
            status(icon: "hourglass", tint: .secondary, spinner: true,
                   title: "Checking usage…", detail: nil)
        case .noCredentials:
            status(icon: "person.crop.circle.badge.questionmark", tint: .secondary,
                   title: "Not signed in",
                   detail: "Sign in to Claude Code and your usage shows up here.")
        case .tokenExpired:
            status(icon: "clock.arrow.circlepath", tint: Palette.ochre,
                   title: "Session expired",
                   detail: "Open Claude Code to refresh — it renews automatically.")
        case .unauthorized:
            status(icon: "lock", tint: Palette.clay,
                   title: "Access denied",
                   detail: "Your token was rejected. Open Claude Code to sign in again.")
        case .offline(nil):
            status(icon: "wifi.slash", tint: .secondary,
                   title: "Can't reach Anthropic",
                   detail: vm.lastErrorMessage ?? "Check your connection. Retrying every 15 minutes.")
        case .live(let s), .offline(.some(let s)):
            usage(s)
        }
    }

    // MARK: - Usage

    private func usage(_ s: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            divider
            VStack(alignment: .leading, spacing: 18) {
                if let w = s.fiveHour {
                    hero(w, severity: s.activeSeverity, snapshot: s)
                }
                if let w = s.sevenDay {
                    secondary(w)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            divider
            footer(updated: s.fetchedAt, retryTitle: "Refresh")
        }
    }

    // The 5-hour window: the one that interrupts a session, so it leads.
    private func hero(_ w: UsageWindow, severity: Severity, snapshot: UsageSnapshot) -> some View {
        let pace = windowElapsedFraction(resetsAt: w.resetsAt,
                                         length: QuotaWindowKind.fiveHour.length)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(QuotaWindowKind.fiveHour.title)
                    .font(.caption).fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(readout(w, snapshot))
                    .font(.system(.title3, design: .rounded)).fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(severity.tint)
            }
            QuotaTrackView(value: fraction(w, snapshot),
                           tint: severity.tint, height: 12, pace: pace)
            if let resets = w.resetsAt {
                (Text("Resets in ") + Text(resets, style: .relative))
                    .font(.caption2).monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // The 7-day window: quiet, secondary, no pace marker — it rarely binds first.
    private func secondary(_ w: UsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(QuotaWindowKind.sevenDay.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(w.utilization.rounded()))%")
                    .font(.caption).fontWeight(.semibold).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            QuotaTrackView(value: w.utilization / 100,
                           tint: Palette.coral.opacity(0.55), height: 6)
            if let resets = w.resetsAt {
                (Text("Resets ") + Text(resets, style: .relative))
                    .font(.caption2).monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Status (non-data states)

    private func status(icon: String, tint: Color, spinner: Bool = false,
                        title: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            divider
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    if spinner {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: icon)
                            .font(.title3).foregroundStyle(tint)
                            .frame(width: 24)
                    }
                    Text(title).font(.callout).fontWeight(.semibold)
                }
                if let detail {
                    Text(detail)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            divider
            footer(updated: nil, retryTitle: "Retry")
        }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Palette.coral)
                .frame(width: 9, height: 9)
            Text("Claude Code").font(.callout).fontWeight(.semibold)
            Spacer()
            if vm.isOffline {
                Image(systemName: "wifi.slash")
                    .font(.caption).foregroundStyle(.secondary)
                    .help("Offline — showing the last update")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var divider: some View { Divider().opacity(0.6) }

    private func footer(updated: Date?, retryTitle: String) -> some View {
        HStack(spacing: 10) {
            if let updated {
                (Text("Updated ") + Text(updated, style: .relative) + Text(" ago"))
                    .font(.caption2).monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            iconButton("arrow.clockwise", help: retryTitle) { vm.refresh() }
            iconButton("power", help: "Quit") { NSApplication.shared.terminate(nil) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func iconButton(_ symbol: String, help: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Readout helpers

    private func readout(_ w: UsageWindow, _ s: UsageSnapshot) -> String {
        switch s.displayMode {
        case .percent:
            return "\(Int(w.utilization.rounded()))%"
        case .dollar:
            return s.spend?.used.map { String(format: "$%.2f", $0.dollars) } ?? "—"
        }
    }

    private func fraction(_ w: UsageWindow, _ s: UsageSnapshot) -> Double {
        switch s.displayMode {
        case .percent:
            return w.utilization / 100
        case .dollar:
            if let used = s.spend?.used?.dollars,
               let limit = s.spend?.limit?.dollars, limit > 0 {
                return used / limit
            }
            return w.utilization / 100
        }
    }
}
