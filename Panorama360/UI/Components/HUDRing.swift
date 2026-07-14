import SwiftUI

/// Rotating tick-marks ring with an optional progress arc — the scanner HUD
/// motif. Wraps the live-globe PiP and decorates the reticle. iOS 16-safe:
/// `TimelineView(.animation)` drives a `Canvas`; rotation is derived from the
/// timeline date (no `phaseAnimator`/`keyframeAnimator`).
struct HUDRing: View {

    var tickCount: Int = 40
    /// Seconds for one full rotation.
    var rotationSeconds: Double = 14
    /// Optional 0..1 arc fill drawn inside the ticks (e.g. coverage %).
    var fill: Double? = nil
    var color: Color = Theme.cyan
    var reverse: Bool = false

    var body: some View {
        TimelineView(.animation) { ctx in
            Canvas { g, size in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let base = (t / rotationSeconds) * 2 * .pi * (reverse ? -1 : 1)
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let r = (min(size.width, size.height) / 2) - 4

                for i in 0..<tickCount {
                    let f = Double(i) / Double(tickCount)
                    let a = base + f * 2 * .pi
                    let major = i.isMultiple(of: 4)
                    let inner = r - (major ? 9 : 4)
                    let p1 = CGPoint(x: c.x + CGFloat(cos(a)) * inner, y: c.y + CGFloat(sin(a)) * inner)
                    let p2 = CGPoint(x: c.x + CGFloat(cos(a)) * r,     y: c.y + CGFloat(sin(a)) * r)
                    var path = Path(); path.move(to: p1); path.addLine(to: p2)
                    g.stroke(path,
                             with: .color(color.opacity(major ? 0.9 : 0.35)),
                             style: StrokeStyle(lineWidth: major ? 1.6 : 1, lineCap: .round))
                }

                if let fill, fill > 0.001 {
                    var arc = Path()
                    arc.addArc(center: c, radius: r + 3,
                               startAngle: .degrees(-90),
                               endAngle: .degrees(-90 + 360 * fill),
                               clockwise: false)
                    g.stroke(arc,
                             with: .color(color.opacity(0.95)),
                             style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                }
            }
        }
    }
}
