import SwiftUI

/// Bottom progress card: segmented bar, count, and ETA.
struct ProgressView360: View {

    let fraction: Double
    let captured: Int
    let total: Int
    let eta: Double
    let stability: Double

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(captured)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("de \(total)")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Label(etaLabel, systemImage: "clock")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.14))
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Color(red: 0.2, green: 0.9, blue: 0.6),
                                     Color(red: 0.25, green: 0.6, blue: 1.0)],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(max(0, min(1, fraction))))
                        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: fraction)
                }
            }
            .frame(height: 8)
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }

    private var etaLabel: String {
        if eta <= 0 { return "—" }
        if eta < 60 { return "\(Int(eta.rounded()))s" }
        return "\(Int((eta / 60).rounded()))m"
    }
}
