import SwiftUI

/// Holographic circular progress ring used on the stitching screen. A rotating
/// scan-glow arcs behind the progress, an angular gradient traces the fill,
/// and an optional center SF Symbol sits above the percentage readout.
/// iOS 16-safe (`TimelineView`, no `phaseAnimator`).
struct CircularProgressView: View {

    let progress: Double          // 0..1
    let lineWidth: CGFloat
    var gradient: [Color] = Theme.successColors
    var centerSymbol: String? = nil
    var symbolColor: Color = Theme.cyan

    init(progress: Double, lineWidth: CGFloat = 10, centerSymbol: String? = nil) {
        self.progress = progress
        self.lineWidth = lineWidth
        self.centerSymbol = centerSymbol
    }

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: lineWidth)

            // Rotating scan-glow behind the fill — keeps the ring "alive".
            TimelineView(.animation) { ctx in
                let deg = (ctx.date.timeIntervalSinceReferenceDate * 42)
                    .truncatingRemainder(dividingBy: 360)
                Circle()
                    .trim(from: 0, to: 0.22)
                    .stroke(
                        LinearGradient(colors: [Theme.cyan.opacity(0), Theme.cyan.opacity(0.55)]),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(deg))
                    .blur(radius: 4)
                    .opacity(0.8)
            }

            // Progress arc
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(AngularGradient(colors: gradient, center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: (gradient.last ?? Theme.cyan).opacity(0.7), radius: 10)
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: progress)

            // Center readout
            VStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(symbolColor)
                        .symbolRenderingMode(.hierarchical)
                }
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
        }
    }
}
