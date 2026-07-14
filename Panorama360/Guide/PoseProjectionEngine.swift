import Foundation
import simd

/// Pose seam for the live reconstruction globe.
///
/// Given the current `DeviceOrientation` (CoreMotion, relative to session
/// start), returns the (yaw, pitch) the globe renderer should use so the filled
/// regions rotate into view as the device turns — i.e. CoreMotion orientation
/// *is* the camera pose for rotate-in-place capture.
///
/// The yaw sign mirrors `ViewerEngine`'s gyro path (`yaw = -attitude.yaw`): at
/// session start the relative orientation is identity, so the first capture sits
/// dead-centre, and turning right brings the next region into view. Centralising
/// it here keeps the convention in one place rather than buried in the renderer.
public enum PoseProjectionEngine {

    public static func liveViewAngles(orientation: DeviceOrientation) -> (yaw: Float, pitch: Float) {
        (-Float(orientation.yaw), Float(orientation.pitch))
    }
}
