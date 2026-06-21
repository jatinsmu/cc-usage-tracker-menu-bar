import SwiftUI

// The popover is a native macOS surface with a Claude-derived accent — not a
// webpage in a window. Backgrounds and text stay on system materials / label
// colors so light/dark and vibrancy work for free; only the *data* accent is
// branded. Add nothing here without a reason that survives both appearances.

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8)  & 0xFF) / 255,
                  blue:  Double( hex        & 0xFF) / 255,
                  opacity: 1)
    }
}

enum Palette {
    static let coral = Color(hex: 0xCC785C)   // normal   — Claude "book cloth"
    static let ochre = Color(hex: 0xC2832F)   // warning
    static let clay  = Color(hex: 0xB23A2E)   // critical — deep clay, not neon red

    static let track = Color.primary.opacity(0.08)   // unused portion
    static let pace  = Color.primary.opacity(0.38)   // window-elapsed marker
}

extension Severity {
    var tint: Color {
        switch self {
        case .normal:   return Palette.coral
        case .warning:  return Palette.ochre
        case .critical: return Palette.clay
        }
    }
}

extension Double {
    func clamped(to r: ClosedRange<Double>) -> Double {
        min(max(self, r.lowerBound), r.upperBound)
    }
}
