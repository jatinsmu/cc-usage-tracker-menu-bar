import SwiftUI

/// The signature element. A rounded usage track whose filled portion (`value`)
/// is the severity tint and whose remainder is a faint neutral. When `pace` is
/// set, a hairline marks how far through the reset window we are — so a fill
/// sitting *ahead* of the tick reads instantly as "burning faster than the clock".
struct QuotaTrackView: View {
    let value: Double            // 0…1, fraction used
    let tint: Color
    var height: CGFloat = 12
    var pace: Double? = nil      // 0…1 fraction of the window elapsed; nil hides it

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let v = value.clamped(to: 0...1)
            let filled = v <= 0 ? 0 : max(height, w * v)

            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track)
                    .frame(height: height)

                Capsule().fill(tint)
                    .frame(width: filled, height: height)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: value)

                if let pace {
                    Rectangle().fill(Palette.pace)
                        .frame(width: 1.5, height: height + 6)
                        .offset(x: (w * pace.clamped(to: 0...1)) - 0.75)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: height + 6)   // headroom for the pace tick overhang
    }
}
