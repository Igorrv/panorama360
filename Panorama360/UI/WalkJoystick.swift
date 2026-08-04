import SwiftUI

/// A minimal virtual joystick: drag inside the pad to produce a normalized
/// vector `[-1, 1]²` via `onChange` (y is inverted so "up" = forward). Snaps to
/// centre on release. No external dependencies.
struct WalkJoystick: View {

    /// Normalized movement vector: dx = strafe, dy = forward (−1…1).
    let onChange: (CGVector) -> Void

    private let radius: CGFloat = 58
    private let knobRadius: CGFloat = 26
    @State private var knob: CGPoint = .zero

    var body: some View {
        ZStack {
            Circle().fill(.black.opacity(0.42))
            Circle().stroke(.white.opacity(0.22), lineWidth: 2)
            Circle().fill(Theme.cyan.opacity(0.9))
                .frame(width: knobRadius * 2, height: knobRadius * 2)
                .offset(x: knob.x, y: knob.y)
                .shadow(color: Theme.cyan.opacity(0.5), radius: 6)
        }
        .frame(width: radius * 2, height: radius * 2)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let dx = v.translation.width
                    let dy = v.translation.height
                    let len = hypot(dx, dy)
                    let clamped = min(len, radius)
                    let nx = len > 0 ? dx / len * clamped : 0
                    let ny = len > 0 ? dy / len * clamped : 0
                    knob = CGPoint(x: nx, y: ny)
                    // Invert y: dragging up (negative dy) ⇒ forward (positive).
                    onChange(CGVector(dx: nx / radius, dy: -ny / radius))
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.2)) { knob = .zero }
                    onChange(.zero)
                }
        )
    }
}
