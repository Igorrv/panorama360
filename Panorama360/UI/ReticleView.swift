import SwiftUI

/// Central aiming reticle: outer ring, inner ring, centre dot. Colour follows
/// proximity (white → yellow → green) and it pulses on each capture.
struct ReticleView: View {

    let state: ReticleState
    let stability: Double
    let pulse: Int

    @State private var pulseScale: CGFloat = 1.0
    @State private var captureFlash: CGFloat = 0

    private var color: Color {
        switch state {
        case .far:     return .white
        case .near:    return Color(red: 1.00, green: 0.80, blue: 0.20)
        case .aligned: return Color(red: 0.20, green: 0.95, blue: 0.45)
        }
    }

    var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .stroke(color.opacity(0.25), lineWidth: 1.5)
                .frame(width: 94, height: 94)
            // Middle ring
            Circle()
                .stroke(color.opacity(0.65), lineWidth: 2)
                .frame(width: 58, height: 58)
            // Centre dot
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.9), radius: 8)

            // Capture flash overlay
            Circle()
                .stroke(color, lineWidth: 2)
                .frame(width: 94, height: 94)
                .scaleEffect(1 + captureFlash)
                .opacity(Double(1 - captureFlash))
        }
        .scaleEffect(pulseScale)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: pulseScale)
        .onChange(of: pulse) { _ in
            triggerCapture()
        }
        .animation(.easeOut(duration: 0.25), value: state)
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
