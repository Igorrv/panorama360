import Foundation
import SwiftUI
import simd
import CoreMotion
import MetalKit

/// Drives the 360° viewer: yaw / pitch / fov, touch drag, pinch zoom, and an
/// optional gyro look. Feeds `PanoramaRenderer` via `makeUniforms()`.
@MainActor
public final class ViewerEngine: ObservableObject {

    @Published public var yaw: Float = 0 {
        didSet { push() }
    }
    @Published public var pitch: Float = 0 {
        didSet { push() }
    }
    @Published public var fov: Float = 1.2 {
        didSet { push() }
    }

    public var sensitivity: Float = 0.005
    public var minFOV: Float = 0.5    // zoomed in  (~28°)
    public var maxFOV: Float = 2.0    // zoomed out (~115°)

    public private(set) var renderer: PanoramaRenderer?
    private var aspect: Float = 1.0

    // Optional gyro look.
    private let motion = CMMotionManager()
    public private(set) var gyroEnabled = false

    public init() {}

    public func attach(renderer: PanoramaRenderer) {
        self.renderer = renderer
        renderer.uniforms.aspect = aspect
        push()
    }

    public func updateAspect(_ size: CGSize) {
        aspect = Float(size.width / max(size.height, 1))
        renderer?.uniforms.aspect = aspect
    }

    // MARK: - Gestures

    public func drag(by translation: CGSize) {
        yaw -= Float(translation.width) * sensitivity
        pitch -= Float(translation.height) * sensitivity
        pitch = max(-1.45, min(1.45, pitch))   // ~±83°
    }

    public func zoom(scale: CGFloat) {
        fov = max(minFOV, min(maxFOV, fov / Float(scale)))
    }

    // MARK: - Gyro (optional)

    public func startGyro() {
        guard motion.isDeviceMotionAvailable, !gyroEnabled else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60
        // Deliver on `.main` and assume main-actor isolation, mutating yaw/pitch
        // directly — avoids the per-sample `Task { @MainActor in }` allocation
        // the previous version did 60×/s. `.main` guarantees main-thread delivery.
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            MainActor.assumeIsolated {
                self.yaw = -Float(data.attitude.yaw) * 0.8
                self.pitch = Float(data.attitude.pitch) * 0.8
            }
        }
        gyroEnabled = true
    }

    public func stopGyro() {
        motion.stopDeviceMotionUpdates()
        gyroEnabled = false
    }

    // MARK: - Uniforms

    private func push() {
        guard let renderer else { return }
        renderer.uniforms = makeUniforms()
    }

    private func makeUniforms() -> ViewerUniforms {
        let yawQ = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
        let pitchQ = simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
        var u = ViewerUniforms()
        u.viewMatrix = simd_float4x4(yawQ) * simd_float4x4(pitchQ)
        u.fovRadians = fov
        u.aspect = aspect
        return u
    }
}
