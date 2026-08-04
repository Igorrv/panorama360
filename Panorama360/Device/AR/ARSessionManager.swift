import ARKit
import simd

/// ARKit world-tracking orientation provider.
///
/// **Important:** ARKit takes exclusive ownership of the camera, so it **cannot
/// run at the same time as `CameraEngine`'s `AVCaptureSession`**. This class is
/// the orientation backend for the alternate "ARKit-owns-the-camera" path, where
/// the live preview comes from `ARFrame.capturedImage` and intrinsics come from
/// `ARCamera.intrinsics` (more accurate than FOV-derived). The default v1 build
/// uses `MotionEngine` + `CameraEngine` because HDR HEIC capture requires
/// `AVCaptureSession`. Switch backends in `CaptureViewModel`.
public final class ARSessionManager: NSObject {

    public let session = ARSession()

    public var onUpdate: ((DeviceOrientation) -> Void)?
    public var onFrame: ((ARFrame) -> Void)?
    public var onReferenceSet: (() -> Void)?

    private var reference: simd_float4x4?
    private var prevQuaternion: simd_quatf?
    private var prevTimestamp: Double?

    public override init() {
        super.init()
        session.delegate = self
    }

    public func run() {
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity
        config.planeDetection = []
        config.isLightEstimationEnabled = false
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    public func pause() {
        session.pause()
    }

    /// Latest camera intrinsics (3×3) — more accurate than FOV-derived.
    public var currentIntrinsics: simd_float3x3? {
        session.currentFrame?.camera.intrinsics
    }

    public func resetReference() {
        reference = nil
        prevQuaternion = nil
        prevTimestamp = nil
    }
}

extension ARSessionManager: ARSessionDelegate {

    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        onFrame?(frame)

        let transform = frame.camera.transform
        if reference == nil {
            reference = transform
            onReferenceSet?()
        }
        guard let reference else { return }

        let relative = OrientationResolver.resolve(transform: transform, reference: reference)
        let look = OrientationResolver.lookDirection(relative: relative)
        let (pitch, yaw) = Geometry.cartesianToSpherical(look)

        let rotationRate = combinedRotationRate(relative: relative, timestamp: frame.timestamp)

        let orientation = DeviceOrientation(
            quaternion: relative,
            pitch: pitch,
            yaw: yaw,
            roll: 0,
            rotationRate: rotationRate,
            gravity: OrientationResolver.gravity(transform: transform),
            timestamp: frame.timestamp
        )
        onUpdate?(orientation)
    }

    private func combinedRotationRate(relative: simd_quatf, timestamp: Double) -> SIMD3<Double> {
        defer {
            prevQuaternion = relative
            prevTimestamp = timestamp
        }
        guard let prevQ = prevQuaternion, let prevT = prevTimestamp else { return .zero }
        let dt = timestamp - prevT
        return OrientationResolver.angularVelocity(from: prevQ, to: relative, delta: dt)
    }
}
