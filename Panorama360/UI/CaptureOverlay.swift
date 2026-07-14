import SwiftUI

/// Draws the floating capture points, an animated aim-assist line from screen
/// centre to the active target, and the per-capture green-check flash.
///
/// Wrapped in `TimelineView(.animation)` so radius/glow/colour update every
/// frame from continuous alignment confidence (smooth "pull" feel) with no
/// per-frame `@State` mutation. Colours come from `Theme`.
struct CaptureOverlay: View {

    @ObservedObject var guide: CaptureGuide

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                var activeTarget: (CGPoint, Color)?

                for point in guide.overlayPoints where !point.captured {
                    guard let position = point.position else { continue }
                    drawPoint(&context, at: position, overlay: point)
                    if activeTarget == nil,
                       point.state == .near || point.state == .aligned {
                        activeTarget = (position, Self.color(for: point.state))
                    }
                }

                // Aim-assist line toward the active target.
                if let target = activeTarget {
                    let phase = (timeline.date.timeIntervalSinceReferenceDate * 40)
                        .truncatingRemainder(dividingBy: 100)
                    var path = Path()
                    path.move(to: center)
                    path.addLine(to: target.0)
                    context.stroke(path, with: .color(target.1.opacity(0.35)),
                                   style: StrokeStyle(lineWidth: 1.4,
                                                      lineCap: .round,
                                                      dash: [3, 7],
                                                      dashPhase: CGFloat(phase)))
                }

                if let flash = guide.lastCapturedFlash {
                    let age = Date().timeIntervalSince(flash.at)
                    if age < 0.5 {
                        drawCheck(&context, at: flash.position, alpha: CGFloat(1 - age / 0.5))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func drawPoint(_ context: inout GraphicsContext,
                           at center: CGPoint,
                           overlay: OverlayPoint) {
        let color = Self.color(for: overlay.state)
        let confidence = overlay.confidence
        let base: CGFloat = 13
        let radius = base * overlay.scale * (0.85 + 0.35 * CGFloat(confidence))

        let rect = CGRect(x: center.x - radius, y: center.y - radius,
                          width: radius * 2, height: radius * 2)

        // Layered glow.
        context.addFilter(.shadow(color: color.opacity(0.9), radius: radius * 1.8))
        context.stroke(Path(ellipseIn: rect), with: .color(color),
                       style: StrokeStyle(lineWidth: 2.4, lineCap: .round))

        // Inner pulsing core.
        let coreRect = rect.insetBy(dx: radius * 0.62, dy: radius * 0.62)
        context.fill(Path(ellipseIn: coreRect), with: .color(color.opacity(0.9)))

        // Aligned points get an extra outer halo.
        if overlay.state == .aligned {
            let halo = rect.insetBy(dx: -7, dy: -7)
            context.stroke(Path(ellipseIn: halo),
                           with: .color(color.opacity(0.35)),
                           style: StrokeStyle(lineWidth: 1))
        }
    }

    private func drawCheck(_ context: inout GraphicsContext, at center: CGPoint, alpha: CGFloat) {
        let symbol = Image(systemName: "checkmark.circle.fill")
        let resolved = context.resolve(
            Text(symbol)
                .font(.system(size: 42, weight: .bold))
                .foregroundColor(Theme.mint))
        context.opacity = alpha
        context.draw(resolved, at: center)
        context.opacity = 1
    }

    static func color(for state: CapturePointState) -> Color { Theme.stateColor(state) }
}
