import SwiftUI

/// Scanner overlay for the capture screen: a soft horizontal line sweeping
/// top→bottom, faint scan bands, and corner brackets framing the viewport.
/// Sits over the live camera; never blocks touches. iOS 16-safe via
/// `TimelineView` (no `phaseAnimator`).
struct ScanlineOverlay: View {

    var color: Color = Theme.cyan
    var period: Double = 3.4

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Soft sweeping glow band.
                TimelineView(.animation) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: period) / period
                    let y = CGFloat(t) * geo.size.height
                    LinearGradient(colors: [.clear, color.opacity(0.30), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 150)
                        .offset(y: y - 75)
                        .blendMode(.plusLighter)
                    // Bright thin core line.
                    Rectangle()
                        .fill(color.opacity(0.7))
                        .frame(height: 1.5)
                        .offset(y: y)
                        .blur(radius: 0.5)
                        .shadow(color: color.opacity(0.9), radius: 6)
                }

                // Corner brackets framing the safe viewport.
                CornerBrackets()
                    .stroke(color.opacity(0.55), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
    }
}

/// Four L-shaped corner brackets inset from the rect edges.
private struct CornerBrackets: Shape {
    var inset: CGFloat = 26
    var len: CGFloat = 24

    func path(in r: CGRect) -> Path {
        var p = Path()
        let (x0, y0, x1, y1) = (r.minX, r.minY, r.maxX, r.maxY)
        // Top-left
        p.move(to: CGPoint(x: x0 + inset,     y: y0 + inset + len))
        p.addLine(to: CGPoint(x: x0 + inset,  y: y0 + inset))
        p.addLine(to: CGPoint(x: x0 + inset + len, y: y0 + inset))
        // Top-right
        p.move(to: CGPoint(x: x1 - inset - len, y: y0 + inset))
        p.addLine(to: CGPoint(x: x1 - inset,    y: y0 + inset))
        p.addLine(to: CGPoint(x: x1 - inset,    y: y0 + inset + len))
        // Bottom-left
        p.move(to: CGPoint(x: x0 + inset, y: y1 - inset - len))
        p.addLine(to: CGPoint(x: x0 + inset, y: y1 - inset))
        p.addLine(to: CGPoint(x: x0 + inset + len, y: y1 - inset))
        // Bottom-right
        p.move(to: CGPoint(x: x1 - inset - len, y: y1 - inset))
        p.addLine(to: CGPoint(x: x1 - inset,    y: y1 - inset))
        p.addLine(to: CGPoint(x: x1 - inset,    y: y1 - inset - len))
        return p
    }
}
