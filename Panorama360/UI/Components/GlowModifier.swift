import SwiftUI

/// Consistent frosted-glass panel styling for overlays (reticle is drawn
/// separately; cards use this).
struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 22
    var opacity: Double = 1.0

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.35 * opacity), radius: 12, y: 4)
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 22) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius))
    }

    /// Soft outer glow.
    func glow(_ color: Color, radius: CGFloat = 10) -> some View {
        shadow(color: color.opacity(0.7), radius: radius)
    }
}
