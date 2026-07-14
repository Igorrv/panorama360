import SwiftUI

/// Central design system — "Scanner Holográfico" identity.
///
/// The single source of truth for color, type, radii and motion. Every screen
/// reads from here instead of scattering RGB literals (which had drifted: two
/// different greens, two navies, three corner radii). Replacing a token here
/// restyles the whole app.
enum Theme {

    // MARK: - Brand palette
    static let cyan   = Color(red: 0.20, green: 0.85, blue: 1.0)
    static let violet = Color(red: 0.55, green: 0.45, blue: 1.0)
    static let mint   = Color(red: 0.20, green: 0.95, blue: 0.45)
    static let amber  = Color(red: 1.00, green: 0.80, blue: 0.20)
    static let gold   = Color(red: 1.00, green: 0.78, blue: 0.25)
    static let ink    = Color(red: 0.03, green: 0.04, blue: 0.09)

    // MARK: - Gradients
    static let auroraColors  = [cyan, violet]
    static let successColors = [mint, cyan]

    /// Brand gradient, diagonal.
    static var aurora: LinearGradient {
        LinearGradient(colors: auroraColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    /// Progress / success gradient, left → right.
    static var progress: LinearGradient {
        LinearGradient(colors: successColors, startPoint: .leading, endPoint: .trailing)
    }
    /// Alias of `progress` — the success gradient, for semantic call sites.
    static var success: LinearGradient { progress }
    /// Screen background: ink → black.
    static var baseGradient: LinearGradient {
        LinearGradient(colors: [ink, .black], startPoint: .top, endPoint: .bottom)
    }

    // MARK: - State → color
    /// One map shared by the reticle and the floating points, so they can never
    /// diverge again. idle/far → cyan, near → amber, aligned → mint (ready).
    static func stateColor(_ state: ReticleState) -> Color {
        switch state {
        case .far:     return cyan
        case .near:    return amber
        case .aligned: return mint
        }
    }

    static func stateColor(_ state: CapturePointState) -> Color {
        switch state {
        case .idle:     return cyan
        case .near:     return amber
        case .aligned:  return mint
        case .captured: return gold
        }
    }

    // MARK: - Radii
    enum R {
        static let sm: CGFloat   = 12
        static let md: CGFloat   = 18
        static let lg: CGFloat   = 24
        static let pill: CGFloat = 100
    }

    // MARK: - Motion
    static let spring     = Animation.spring(response: 0.40, dampingFraction: 0.72)
    static let snappy     = Animation.spring(response: 0.28, dampingFraction: 0.78)
    static let slowSpring = Animation.spring(response: 0.55, dampingFraction: 0.82)
}

// MARK: - Typography

extension Font {
    /// App type scale. `.rounded` for UI, `.monospaced` (`hud`) for instrument
    /// readouts — the scanner feel.
    enum App {
        static let largeTitle = Font.system(size: 30, weight: .bold,      design: .rounded)
        static let title      = Font.system(size: 24, weight: .bold,      design: .rounded)
        static let headline   = Font.system(size: 18, weight: .semibold,  design: .rounded)
        static let body       = Font.system(size: 16, weight: .regular,   design: .rounded)
        static let caption    = Font.system(size: 13, weight: .medium,    design: .rounded)
        static let micro      = Font.system(size: 10, weight: .semibold,  design: .rounded)
        static let hud        = Font.system(size: 13, weight: .semibold,  design: .monospaced)
        static let hudLarge   = Font.system(size: 22, weight: .bold,      design: .monospaced)
    }
}
