import Foundation
import simd

/// Snapshot of how still the device is at an instant.
public struct Stability: Sendable, Equatable {
    /// 0 (moving) … 1 (rock solid).
    public let score: Double
    /// Smoothed angular speed (rad/s).
    public let angularSpeed: Double
    public let isStable: Bool

    public init(score: Double, angularSpeed: Double, isStable: Bool) {
        self.score = score
        self.angularSpeed = angularSpeed
        self.isStable = isStable
    }
}

/// Low-pass-filters angular speed into a stability score. Stateless-ish: mutate
/// a shared instance per session.
public struct StabilityEstimator {

    /// Max angular speed considered "still" (rad/s). ~3°/s.
    public var stabilityThreshold: Double
    /// EMA smoothing factor (0…1); smaller = smoother/laggier.
    public var smoothing: Double

    private var smoothedSpeed: Double = 0
    private var primed: Bool = false

    public init(stabilityThreshold: Double = 0.06, smoothing: Double = 0.25) {
        self.stabilityThreshold = stabilityThreshold
        self.smoothing = smoothing
    }

    public mutating func ingest(_ orientation: DeviceOrientation) -> Stability {
        let raw = orientation.angularSpeed
        if !primed {
            smoothedSpeed = raw
            primed = true
        } else {
            smoothedSpeed = smoothing * raw + (1 - smoothing) * smoothedSpeed
        }
        let ratio = min(smoothedSpeed / max(stabilityThreshold, 1e-6), 1.0)
        let score = 1.0 - ratio
        return Stability(score: score,
                         angularSpeed: smoothedSpeed,
                         isStable: smoothedSpeed <= stabilityThreshold)
    }

    public mutating func reset() {
        smoothedSpeed = 0
        primed = false
    }
}
