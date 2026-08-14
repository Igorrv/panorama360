import Foundation
import CoreMotion
import simd

/// Streams `DeviceOrientation` samples (relative to a start reference) from
/// CoreMotion device motion. The single orientation source for the v1 pipeline.
public final class MotionEngine {

    public enum MotionError: LocalizedError {
        case unavailable
        public var errorDescription: String? {
            return "Device motion is not available on this device."
        }
    }

    private let manager = CMMotionManager()
    private let queue = OperationQueue()
    private var reference: simd_quatf?
    private var referencePrimed = false

    /// Called on a background queue for every device-motion update.
    public var onUpdate: ((DeviceOrientation) -> Void)?
    /// Called once when the start reference has been captured.
    public var onReferenceSet: (() -> Void)?

    public init() {
        queue.qualityOfService = .userInteractive
        queue.name = "com.teleport.motion"
    }

    public var isRunning: Bool { manager.isDeviceMotionActive }

    /// Default 30 Hz (was 60). Each update hops to the main actor for guide UI,
    /// so halving the rate halves that load — important on the capture screen
    /// where the main actor also runs the gate + Canvas redraws. 30 Hz is plenty
    /// for alignment and stability.
    public func start(interval: TimeInterval = 1.0 / 30.0) throws {
        guard manager.isDeviceMotionAvailable else { throw MotionError.unavailable }
        manager.deviceMotionUpdateInterval = interval
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] data, _ in
            guard let self, let data = data else { return }
            self.process(data)
        }
    }

    public func stop() {
        manager.stopDeviceMotionUpdates()
        // The session reference is intentionally PRESERVED here. Clearing it
        // would force the next update to re-anchor the heading origin, so photos
        // captured across a stop/start (e.g. a suspend/resume) would end up in
        // two different frames and misalign in the stitch. The reference is
        // scoped to this instance's lifetime — a new session builds a new engine.
    }

    // MARK: - Processing

    private func process(_ data: CMDeviceMotion) {
        let current = simd_quatf(data.attitude.quaternion)

        // First stable-ish sample becomes the reference (baseline) frame.
        if !referencePrimed {
            reference = current
            referencePrimed = true
            onReferenceSet?()
        }
        guard let ref = reference else { return }

        let relative = simd_mul(simd_inverse(ref), current)
        let look = relative.act(DeviceOrientation.backCameraAxis)
        let (pitch, yaw) = Geometry.cartesianToSpherical(look)

        let orientation = DeviceOrientation(
            quaternion: relative,
            pitch: pitch,
            yaw: yaw,
            roll: data.attitude.roll,
            rotationRate: SIMD3<Double>(data.rotationRate.x,
                                        data.rotationRate.y,
                                        data.rotationRate.z),
            gravity: SIMD3<Double>(data.gravity.x, data.gravity.y, data.gravity.z),
            timestamp: data.timestamp
        )
        onUpdate?(orientation)
    }

    /// Force the reference to be re-captured on the next update (e.g. after a pause).
    public func resetReference() {
        reference = nil
        referencePrimed = false
    }
}

// MARK: - CMQuaternion → simd_quatf

public extension simd_quatf {
    init(_ q: CMQuaternion) {
        self.init(ix: Float(q.x), iy: Float(q.y), iz: Float(q.z), r: Float(q.w))
    }
}
