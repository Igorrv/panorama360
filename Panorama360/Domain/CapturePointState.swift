import Foundation

/// Lifecycle state of a single virtual capture point.
///
/// Color mapping (applied in the UI layer, not here, to keep Domain UI-free):
/// - `idle`     → green   (not yet photographed)
/// - `near`     → yellow  (device is approaching the target)
/// - `aligned`  → blue    (device is on target; capture gate evaluates)
/// - `captured` → fades out with animation
public enum CapturePointState: String, Codable, Sendable, CaseIterable {
    case idle
    case near
    case aligned
    case captured
}

// MARK: - Alignment thresholds

/// Angular thresholds (radians) that drive the state machine.
public struct AlignmentThresholds: Sendable, Equatable {
    /// Distance at which a point transitions `idle → near`.
    public let nearDistance: Double
    /// Distance at which a point transitions `near → aligned`.
    public let alignedDistance: Double

    public init(nearDistance: Double, alignedDistance: Double) {
        self.nearDistance = nearDistance
        self.alignedDistance = alignedDistance
    }

    /// Default tuned to match the relaxed `CaptureGate` window so the reticle
    /// turns "aligned" at the same moment the gate is allowed to fire.
    public static let `default` = AlignmentThresholds(
        nearDistance: radians(26),    // ~26°
        alignedDistance: radians(7)   // ~7°  (matches CaptureGate.alignedDistance)
    )

    /// Resolve a state from an angular distance to target.
    public func state(forDistance radians: Double) -> CapturePointState {
        if radians <= alignedDistance { return .aligned }
        if radians <= nearDistance { return .near }
        return .idle
    }
}

// MARK: - Convenience

@inlinable
public func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }

@inlinable
public func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
