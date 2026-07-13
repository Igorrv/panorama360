import Foundation
import simd

/// Device orientation at an instant, expressed relative to the session's
/// **start frame** (captured when guidance begins). Drives alignment, the
/// reticle, stability, and the per-shot quaternion stored with each photo.
public struct DeviceOrientation: Sendable, Equatable {
    /// Relative rotation since start (start⁻¹ · current). Used by the stitcher.
    public let quaternion: simd_quatf
    /// Elevation of the camera axis in the start frame (radians, +up / −down).
    public let pitch: Double
    /// Heading of the camera axis in the start frame (radians).
    public let yaw: Double
    /// Roll about the camera axis (radians) — diagnostics only.
    public let roll: Double
    /// Instantaneous rotation rate (rad/s).
    public let rotationRate: SIMD3<Double>
    /// Gravitational direction in the start frame (for horizon cues).
    public let gravity: SIMD3<Double>
    public let timestamp: Double

    public init(quaternion: simd_quatf,
                pitch: Double, yaw: Double, roll: Double,
                rotationRate: SIMD3<Double>,
                gravity: SIMD3<Double>,
                timestamp: Double) {
        self.quaternion = quaternion
        self.pitch = pitch
        self.yaw = yaw
        self.roll = roll
        self.rotationRate = rotationRate
        self.gravity = gravity
        self.timestamp = timestamp
    }

    /// Magnitude of angular velocity (rad/s) — primary stability signal.
    public var angularSpeed: Double {
        simd_length(rotationRate)
    }

    /// Camera look direction in the start frame.
    public var lookDirection: SIMD3<Float> {
        quaternion.act(Self.backCameraAxis)
    }

    /// Back-camera axis in the CoreMotion device frame (screen‑face‑up: +Z out
    /// of glass, so the rear lens points along −Z).
    public static let backCameraAxis = SIMD3<Float>(0, 0, -1)
}
