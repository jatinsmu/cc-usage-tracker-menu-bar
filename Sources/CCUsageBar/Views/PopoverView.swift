import SwiftUI

struct PopoverView: View {
    @EnvironmentObject private var vm: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            stateContent
        }
        .frame(width: 300)
    }

    // MARK: - State router

    @ViewBuilder
    private var stateContent: some View {
        switch vm.state {
        case .loading:
            placeholderView(
                symbol: "arrow.clockwise",
                title: "Loading...",
                detail: nil
            )
        case .noCredentials:
            placeholderView(
                symbol: "person.slash",
                title: "Not connected",
                detail: "Sign in to Claude Code to get started."
            )
        case .tokenExpired:
            placeholderView(
                symbol: "exclamationmark.triangle",
                title: "Session expired",
                detail: "Open Claude Code to refresh your session."
            )
        case .unauthorized:
            placeholderView(
                symbol: "lock.slash",
                title: "Unauthorized",
                detail: "Token rejected by API. Open Claude Code to sign in again."
            )
        case .offline(nil):
            placeholderView(
                symbol: "wifi.slash",
                title: "Offline",
                detail: vm.lastErrorMessage ?? "Could not reach api.anthropic.com. Retrying every 60s."
            )
        case .live(let s), .offline(.some(let s)):
            usageContent(snapshot: s)
        }
    }

    // MARK: - Usage view

    private func usageContent(snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Claude Code Usage")
                    .font(.headline)
                Spacer()
                if vm.isOffline {
                    Image(systemName: "wifi.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding([.horizontal, .top])
            .padding(.bottom, 10)

            Divider()

            // Quota bars
            VStack(alignment: .leading, spacing: 14) {
                if let w = snapshot.fiveHour {
                    QuotaBarView(
                        label: "5-hour window",
                        value: w.utilization / 100.0,
                        displayText: pctString(w.utilization),
                        resetsAt: w.resetsAt,
                        severity: snapshot.activeSeverity
                    )
                }
                if let w = snapshot.sevenDay {
                    QuotaBarView(
                        label: "7-day window",
                        value: w.utilization / 100.0,
                        displayText: pctString(w.utilization),
                        resetsAt: w.resetsAt,
                        severity: .normal
                    )
                }
            }
            .padding()

            Divider()

            // Footer
            HStack(spacing: 8) {
                Text("Updated \(snapshot.fetchedAt, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Refresh") { vm.refresh() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("·").foregroundStyle(.tertiary)
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Placeholder

    private func placeholderView(symbol: String, title: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.headline)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack(spacing: 8) {
                Spacer()
                Button("Retry") { vm.refresh() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("·").foregroundStyle(.tertiary)
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    // MARK: - Helpers

    private func pctString(_ v: Double) -> String { "\(Int(v.rounded()))%" }
}
