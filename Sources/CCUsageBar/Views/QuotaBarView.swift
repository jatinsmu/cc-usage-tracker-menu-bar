import SwiftUI

struct QuotaBarView: View {
    let label: String
    let value: Double        // 0…1
    let displayText: String
    let resetsAt: Date?
    let severity: Severity

    private var barColor: Color {
        switch severity {
        case .normal:   return .blue
        case .warning:  return .orange
        case .critical: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(displayText)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            ProgressView(value: value.clamped(to: 0...1))
                .tint(barColor)
            if let resetsAt {
                Text("Resets \(resetsAt, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
