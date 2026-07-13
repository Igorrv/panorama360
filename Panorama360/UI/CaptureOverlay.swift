import SwiftUI

/// Draws the floating capture points (Canvas, redrawn every frame for fluidity).
/// Each point glows and scales with proximity; captured points vanish.
struct CaptureOverlay: View {

    @ObservedObject var guide: CaptureGuide

    var body: some View {
        Canvas { context, _ in
            for point in guide.overlayPoints where !point.captured {
                guard let position = point.position else { continue }
                drawPoint(&context, at: position, overlay: point)
            }
        }
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

        // Glow via a soft shadow filter.
        context.addFilter(.shadow(color: color.opacity(0.9), radius: radius * 1.6))
        context.stroke(Path(ellipseIn: rect), with: .color(color),
                       style: StrokeStyle(lineWidth: 2.4, lineCap: .round))

        // Inner pulsing core.
        let coreRect = rect.insetBy(dx: radius * 0.62, dy: radius * 0.62)
        context.fill(Path(ellipseIn: coreRect), with: .color(color.opacity(0.9)))

        // Aligned points get an extra outer halo.
        if overlay.state == .aligned {
            let halo = rect.insetBy(dx: -6, dy: -6)
            context.stroke(Path(ellipseIn: halo),
                           with: .color(color.opacity(0.35)),
                           style: StrokeStyle(lineWidth: 1))
        }
    }

    static func color(for state: CapturePointState) -> Color {
        switch state {
        case .idle:    return Color(red: 0.20, green: 0.95, blue: 0.45)   // green
        case .near:    return Color(red: 1.00, green: 0.80, blue: 0.20)   // yellow
        case .aligned: return Color(red: 0.25, green: 0.60, blue: 1.00)   // blue
        case .captured: return .clear
        }
    }
}
