import SwiftUI

/// Frosted-glass panel styling — the canonical card recipe. Adds an inner top
/// sheen and an optional tinted edge glow so panels can carry the scanner
/// accent. Backward-compatible: `.glassPanel()` keeps working unchanged.
struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = Theme.R.lg
    var opacity: Double = 1.0
    /// Optional accent: tints the fill faintly and brightens the top edge.
    var tint: Color? = nil

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    // Inner top sheen — the glass "catches the light".
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0.18), .clear],
                                             startPoint: .top, endPoint: .center))
                    if let tint {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint.opacity(0.10))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(colors: [(tint ?? .white).opacity(tint == nil ? 0.12 : 0.55),
                                                 .white.opacity(0.05)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35 * opacity), radius: 12, y: 4)
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = Theme.R.lg, tint: Color? = nil) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius, tint: tint))
    }

    /// Soft outer glow (now actually used across the app).
    func glow(_ color: Color, radius: CGFloat = 10) -> some View {
        shadow(color: color.opacity(0.7), radius: radius)
    }
}
