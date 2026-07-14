import SwiftUI

/// Sweeping highlight that travels left → right across any view. Used on
/// progress bars, CTAs and the progress ring for the "active / processing"
/// feel. iOS 16-safe: `TimelineView` + a translucent gradient band; no
/// `phaseAnimator` (iOS 17).
struct Shimmer: ViewModifier {

    var active: Bool = true
    var tint: Color = .white
    /// Seconds for one full sweep.
    var period: Double = 2.4

    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { geo in
                TimelineView(.animation) { ctx in
                    let w = geo.size.width
                    let bandW = max(40, w * 0.45)
                    let t = ctx.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: period) / period
                    let x = CGFloat(t) * (w + bandW) - bandW
                    LinearGradient(colors: [.clear, tint.opacity(0.55), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: bandW, height: geo.size.height)
                        .offset(x: x)
                        .blur(radius: 1)
                        .opacity(active ? 1 : 0)
                        .blendMode(.plusLighter)
                }
            }
            .allowsHitTesting(false)
        )
    }
}

extension View {
    /// Adds a left→right shimmering highlight. Inactive when `active` is false.
    func shimmer(active: Bool = true, tint: Color = .white, period: Double = 2.4) -> some View {
        modifier(Shimmer(active: active, tint: tint, period: period))
    }
}
