import SwiftUI

/// Animated aurora background for non-camera screens (onboarding, stitching).
/// Drifting cyan / violet / mint radial blobs brighten the ink base; a faint
/// HUD grid + edge vignette add depth. iOS 16-safe: only `TimelineView` +
/// `Canvas` (no `MeshGradient`, which is iOS 18). Place behind content with
/// `.ignoresSafeArea()`.
struct HoloBackground: View {

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()

            // Drifting aurora blobs (additive → glow on the ink).
            TimelineView(.animation) { ctx in
                Canvas { g, size in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    Self.blob(g, size, t, 0.0, Theme.cyan,   0.22, 0.75, 0.50)
                    Self.blob(g, size, t, 2.1, Theme.violet, 0.26, 0.70, 0.42)
                    Self.blob(g, size, t, 4.3, Theme.mint,   0.16, 0.55, 0.30)
                }
            }
            .blendMode(.plusLighter)
            .ignoresSafeArea()

            // Faint static HUD grid.
            Canvas { g, size in
                let step: CGFloat = 38
                var x = step
                while x < size.width {
                    Self.line(g, CGPoint(x: x, y: 0), CGPoint(x: x, y: size.height), 0.05)
                    x += step
                }
                var y = step
                while y < size.height {
                    Self.line(g, CGPoint(x: 0, y: y), CGPoint(x: size.width, y: y), 0.05)
                    y += step
                }
            }
            .opacity(0.7)
            .ignoresSafeArea()

            // Edge vignette.
            RadialGradient(
                colors: [.clear, .black.opacity(0.55)],
                center: .center,
                startRadius: 0,
                endRadius: 460)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Canvas helpers

    private static func blob(_ g: GraphicsContext, _ size: CGSize, _ t: Double,
                             _ phase: Double, _ color: Color,
                             _ amp: Double, _ radius: CGFloat, _ strength: Double) {
        let cx = size.width  * (0.5 + amp * sin(t * 0.13 + phase))
        let cy = size.height * (0.5 + amp * sin(t * 0.09 + phase * 1.4))
        let r = min(size.width, size.height) * radius
        g.fill(Path(CGRect(origin: .zero, size: size)),
               with: .radialGradient(
                Gradient(colors: [color.opacity(strength),
                                  color.opacity(strength * 0.25),
                                  .clear]),
                center: CGPoint(x: cx, y: cy),
                startRadius: 0, endRadius: r))
    }

    private static func line(_ g: GraphicsContext, _ a: CGPoint, _ b: CGPoint, _ opacity: Double) {
        var p = Path(); p.move(to: a); p.addLine(to: b)
        g.stroke(p, with: .color(Theme.cyan.opacity(opacity)), lineWidth: 1)
    }
}
