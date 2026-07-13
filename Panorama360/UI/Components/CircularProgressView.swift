import SwiftUI

/// A futuristic circular progress ring used on the stitching screen.
struct CircularProgressView: View {

    let progress: Double          // 0..1
    let lineWidth: CGFloat
    var gradient: [Color] = [
        Color(red: 0.2, green: 0.9, blue: 0.6),
        Color(red: 0.25, green: 0.6, blue: 1.0)
    ]

    init(progress: Double, lineWidth: CGFloat = 10) {
        self.progress = progress
        self.lineWidth = lineWidth
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(AngularGradient(colors: gradient, center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: gradient.last?.opacity(0.6) ?? .clear, radius: 10)
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: progress)

            VStack(spacing: 2) {
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
        }
    }
}
