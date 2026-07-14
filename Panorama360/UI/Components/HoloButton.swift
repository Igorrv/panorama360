import SwiftUI

/// Reusable holographic button: gradient (or glass) fill, hairline border,
/// accent glow and a press-scale. Replaces the ad-hoc CTA styling scattered
/// across onboarding / capture. Callers own the label typography.
struct HoloButton: ButtonStyle {

    /// `nil` → frosted-glass only; otherwise a gradient fill.
    var gradient: [Color]? = Theme.auroraColors
    var fills: Bool = true
    var cornerRadius: CGFloat = Theme.R.md

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .frame(maxWidth: fills ? .infinity : nil)
            .background(
                Group {
                    if let gradient {
                        LinearGradient(colors: gradient,
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing)
                    } else {
                        Color.white.opacity(0.10)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.28), lineWidth: 1)
            )
            .shadow(color: (gradient?.last ?? Theme.cyan).opacity(0.45), radius: 14, y: 6)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Theme.snappy, value: configuration.isPressed)
    }
}
