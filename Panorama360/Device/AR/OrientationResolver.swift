import Foundation
import ARKit
import simd

/// Converts an ARKit camera pose into the same `DeviceOrientation` shape the
/// CoreMotion path emits, so downstream consumers (guide, gate, stitcher) are
/// agnostic to the orientation source.
public enum OrientationResolver {

    /// Builds a relative orientation from the current ARKit camera transform.
    /// - Parameters:
    ///   - transform: `frame.camera.transform`.
    ///   - reference: start-frame world transform.
    public static func resolve(transform: simd_float4x4,
                               reference: simd_float4x4) -> simd_quatf {
        let refQ = simd_quatf(reference)
        let camQ = simd_quatf(transform)
        return simd_mul(simd_inverse(refQ), camQ)
    }

    /// Look direction (camera forward, −Z) expressed in the start frame.
    public static func lookDirection(relative: simd_quatf) -> SIMD3<Float> {
        relative.act(DeviceOrientation.backCameraAxis)
    }

    /// Gravity expressed in the device frame, derived from the ARKit camera
    /// pose. Valid because the session runs with `worldAlignment = .gravity`,
    /// so world −Y always points down.
    public static func gravity(transform: simd_float4x4) -> SIMD3<Double> {
        let camQ = simd_quatf(transform)
        let g = simd_inverse(camQ).act(SIMD3<Float>(0, -1, 0))
        return SIMD3<Double>(Double(g.x), Double(g.y), Double(g.z))
    }

    /// Angular velocity (rad/s) from two consecutive relative quaternions.
    public static func angularVelocity(from previous: simd_quatf,
                                       to current: simd_quatf,
                                       delta seconds: Double) -> SIMD3<Double> {
        guard seconds > 1e-5 else { return .zero }
        let deltaQ = simd_mul(current, simd_inverse(previous))
        let angle = 2 * acos(min(max(deltaQ.real, -1), 1))
        guard angle > 1e-5 else { return .zero }
        let axis = simd_normalize(SIMD3<Float>(deltaQ.vector.x, deltaQ.vector.y, deltaQ.vector.z))
        let speed = Float(Double(angle) / seconds)
        let v = axis * speed
        return SIMD3<Double>(Double(v.x), Double(v.y), Double(v.z))
    }
}
