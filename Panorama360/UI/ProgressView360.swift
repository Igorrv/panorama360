import SwiftUI

/// Bottom progress card. In fixed mode shows "X de Y" + ETA; in coverage
/// (dynamic) mode shows "Cobertura NN%" + the photo count. Holographic styling:
/// glass panel, monospaced readouts and a shimmering gradient bar.
struct ProgressView360: View {

    let fraction: Double
    let captured: Int
    let total: Int
    let eta: Double
    let stability: Double
    /// Non-nil in dynamic mode — switches the card to coverage display.
    var coverageFraction: Double? = nil

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                if let cov = coverageFraction {
                    Text("Cobertura ")
                        .font(.App.caption)
                        .foregroundStyle(.white.opacity(0.6))
                    + Text("\(Int((cov * 100).rounded()))%")
                        .font(.App.hudLarge)
                        .foregroundStyle(Theme.success)
                    Spacer()
                    Label("\(captured) fotos", systemImage: "camera")
                        .font(.App.hud)
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    Text("\(captured)")
                        .font(.App.hudLarge)
                        .foregroundStyle(Theme.success)
                    Text("de \(total)")
                        .font(.App.caption)
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Label(etaLabel, systemImage: "clock")
                        .font(.App.hud)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(Theme.progress)
                        .frame(width: geo.size.width * CGFloat(max(0, min(1, fraction))))
                        .shimmer(active: fraction > 0.001 && fraction < 0.999, tint: .white)
                        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: fraction)
                }
            }
            .frame(height: 9)
        }
        .padding(18)
        .glassPanel(cornerRadius: Theme.R.lg, tint: Theme.cyan)
    }

    private var etaLabel: String {
        if eta <= 0 { return "—" }
        if eta < 60 { return "\(Int(eta.rounded()))s" }
        return "\(Int((eta / 60).rounded()))m"
    }
}
