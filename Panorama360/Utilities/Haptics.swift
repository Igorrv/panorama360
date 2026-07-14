import UIKit
import AudioToolbox

/// Centralised haptic feedback for the capture flow.
/// All generators are pre-prepared on first use to minimise latency.
public final class Haptics {
    public static let shared = Haptics()

    private let impactLight  = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactRigid  = UIImpactFeedbackGenerator(style: .rigid)
    private let selection    = UISelectionFeedbackGenerator()
    private let notify       = UINotificationFeedbackGenerator()

    private init() {}

    /// Call once (e.g. on capture screen appear) so hardware is warmed up.
    public func prepare() {
        [impactLight, impactMedium, impactRigid, selection, notify].forEach { $0.prepare() }
    }

    /// User moves into the "near" band of a point.
    public func approaching() {
        impactLight.impactOccurred(intensity: 0.4)
        impactLight.prepare()
    }

    /// A point just became "aligned" — ready to capture.
    public func aligned() {
        impactMedium.impactOccurred(intensity: 0.7)
        impactMedium.prepare()
    }

    /// A photo was captured successfully.
    public func captured() {
        impactRigid.impactOccurred(intensity: 1.0)
        notify.notificationOccurred(.success)
        impactRigid.prepare()
    }

    /// Subtle camera-shutter sound (system ID 1108). No audio asset bundled, and
    /// it honours the mute switch. Played alongside `captured()` for the
    /// per-capture feedback sequence.
    public func shutterSound() {
        AudioServicesPlaySystemSound(1108)
    }

    /// Capture aborted or session cancelled.
    public func cancelled() {
        notify.notificationOccurred(.warning)
        notify.prepare()
    }

    /// Stitching finished.
    public func finished() {
        notify.notificationOccurred(.success)
        notify.prepare()
    }
}
