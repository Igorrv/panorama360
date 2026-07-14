import SwiftUI

/// Precision scanner reticle: faint guide ring, rotating tick ring, a radar
/// confidence arc (cyan → mint when capture-ready), corner brackets, a
/// crosshair, and a capture flash burst. Colours follow `Theme.stateColor`.
struct ReticleView: View {

    let state: ReticleState
    /// 0..1 capture confidence (alignment + stability + sharpness) — drives the arc.
    let confidence: Double
    let pulse: Int

    @State private var pulseScale: CGFloat = 1.0
    @State private var captureFlash: CGFloat = 0

    private var color: Color { Theme.stateColor(state) }
    private var ready: Bool { confidence >= 0.7 }

    var body: some View {
        ZStack {
            // Faint outer guide ring.
            Circle()
                .stroke(color.opacity(0.15), lineWidth: 1)
                .frame(width: 122, height: 122)

            // Rotating tick ring (scanner motif).
            HUDRing(tickCount: 48, rotationSeconds: 16, color: color)
                .frame(width: 108, height: 108)
                .opacity(0.85)

            // Radar confidence arc.
            ConfidenceArc(progress: confidence, color: ready ? Theme.mint : color)
                .frame(width: 88, height: 88)

            // Corner brackets.
            Brackets()
                .stroke(color.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 70, height: 70)

            // Crosshair + centre dot.
            Crosshair()
                .stroke(color.opacity(0.55), lineWidth: 1)
                .frame(width: 34, height: 34)
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.9), radius: 8)

            // Capture flash burst.
            Circle()
                .stroke(color, lineWidth: 2)
                .frame(width: 122, height: 122)
                .scaleEffect(1 + captureFlash)
                .opacity(Double(1 - captureFlash))
        }
        .scaleEffect(pulseScale)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: pulseScale)
        .animation(.easeOut(duration: 0.25), value: state)
        .onChange(of: pulse) { _ in triggerCapture() }
    }

    private func triggerCapture() {
        withAnimation(.easeOut(duration: 0.45)) {
            pulseScale = 1.25
            captureFlash = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                pulseScale = 1.0
                captureFlash = 0
            }
        }
    }
}

// MARK: - Confidence arc

private struct ConfidenceArc: View {
    let progress: Double
    let color: Color

    var body: some View {
        Circle()
            .trim(from: 0, to: max(0.001, min(1, progress)))
            .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .shadow(color: color.opacity(0.8), radius: 6)
            .animation(Theme.spring, value: progress)
    }
}

// MARK: - Shapes

/// Four short L-shaped corner brackets at the rect edges.
private struct Brackets: Shape {
    var len: CGFloat = 13
    func path(in r: CGRect) -> Path {
        var p = Path()
        let (x0, y0, x1, y1) = (r.minX, r.minY, r.maxX, r.maxY)
        p.addLines([CGPoint(x: x0, y: y0 + len), CGPoint(x: x0, y: y0), CGPoint(x: x0 + len, y: y0)])
        p.addLines([CGPoint(x: x1 - len, y: y0), CGPoint(x: x1, y: y0), CGPoint(x: x1, y: y0 + len)])
        p.addLines([CGPoint(x: x0, y: y1 - len), CGPoint(x: x0, y: y1), CGPoint(x: x0 + len, y: y1)])
        p.addLines([CGPoint(x: x1 - len, y: y1), CGPoint(x: x1, y: y1), CGPoint(x: x1, y: y1 - len)])
        return p
    }
}

/// A thin "+" crosshair centred in the rect.
private struct Crosshair: Shape {
    var arm: CGFloat = 6
    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY)
        var p = Path()
        p.move(to: CGPoint(x: c.x - arm, y: c.y)); p.addLine(to: CGPoint(x: c.x + arm, y: c.y))
        p.move(to: CGPoint(x: c.x, y: c.y - arm)); p.addLine(to: CGPoint(x: c.x, y: c.y + arm))
        return p
    }
}
