import Foundation
import simd
import CoreGraphics
#if canImport(UIKit)
import UIKit
#endif

/// Spherical / vector geometry for alignment and screen projection.
///
/// **Convention.** Points are authored in the *session-local frame*: at session
/// start the device's forward axis is the −Z axis, +Y is up, +X is right.
/// `sphericalToCartesian(yaw=0, pitch=0)` therefore returns `(0, 0, -1)`.
public enum Geometry {

    // MARK: - Spherical ↔ Cartesian

    /// (pitch, yaw) → unit vector in the session-local frame.
    public static func sphericalToCartesian(pitch: Double, yaw: Double) -> simd_double3 {
        let cp = cos(pitch)
        return simd_double3(-sin(yaw) * cp,
                            sin(pitch),
                            -cos(yaw) * cp)
    }

    public static func sphericalToCartesianf(pitch: Double, yaw: Double) -> SIMD3<Float> {
        let v = sphericalToCartesian(pitch: pitch, yaw: yaw)
        return SIMD3<Float>(Float(v.x), Float(v.y), Float(v.z))
    }

    public static func cartesianToSpherical(_ v: SIMD3<Float>) -> (pitch: Double, yaw: Double) {
        let n = simd_normalize(v)
        let pitch = asin(Double(n.y).clamped(to: -1...1))
        let yaw = atan2(Double(-n.x), Double(-n.z))
        return (pitch, yaw)
    }

    // MARK: - Angular distance

    /// Great-circle distance between two unit vectors (radians), numerically safe.
    public static func angularDistance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let d = simd_clamp(simd_dot(simd_normalize(a), simd_normalize(b)), -1, 1)
        return acos(d)
    }

    public static func angularDistance(_ a: simd_double3, _ b: simd_double3) -> Double {
        let d = simd_clamp(simd_dot(simd_normalize(a), simd_normalize(b)), -1, 1)
        return acos(d)
    }

    /// Angular distance from current (pitch,yaw) to a target (pitch,yaw).
    public static func angularDistance(pitch p1: Double, yaw y1: Double,
                                       pitch p2: Double, yaw y2: Double) -> Double {
        angularDistance(sphericalToCartesian(pitch: p1, yaw: y1),
                        sphericalToCartesian(pitch: p2, yaw: y2))
    }

    // MARK: - Camera orientation helpers

    /// Forward direction (where the lens points) of an ARKit camera transform.
    public static func forwardVector(of transform: simd_float4x4) -> SIMD3<Float> {
        -SIMD3<Float>(transform[2].x, transform[2].y, transform[2].z)
    }

    /// Current forward direction expressed in the session-local (start) frame.
    /// This is what guide points (also authored in the start frame) are compared to.
    public static func relativeForward(currentTransform: simd_float4x4,
                                       startTransform: simd_float4x4) -> SIMD3<Float> {
        let fwdWorld = forwardVector(of: currentTransform)
        // Express fwdWorld in start-local basis: rotate by inverse of start rotation.
        let startRot = simd_quatf(startTransform)
        let invStart = simd_inverse(startRot)
        return invStart.act(fwdWorld)
    }

    // MARK: - Screen projection (best-effort overlay placement)

    #if canImport(UIKit)
    /// Projects a session-local direction onto the viewport.
    /// Returns `nil` when the direction is behind the camera.
    public static func project(direction localDir: SIMD3<Float>,
                               startTransform: simd_float4x4,
                               cameraTransform: simd_float4x4,
                               intrinsics: simd_float3x3,
                               imageSize: CGSize,
                               viewport: CGSize,
                               orientation: UIInterfaceOrientation) -> CGPoint? {
        // 1. Session-local → world.
        let startRot = simd_quatf(startTransform)
        let worldDir = startRot.act(localDir)

        // 2. World → camera-image frame (x right, y down, z forward).
        let camRight  = SIMD3<Float>(cameraTransform[0].x, cameraTransform[0].y, cameraTransform[0].z)
        let camUp     = SIMD3<Float>(cameraTransform[1].x, cameraTransform[1].y, cameraTransform[1].z)
        let camFwd    = forwardVector(of: cameraTransform)

        let z = simd_dot(worldDir, camFwd)
        guard z > 1e-4 else { return nil }            // behind / parallel to sensor
        let x = simd_dot(worldDir, camRight) / z
        let y = -simd_dot(worldDir, camUp) / z        // image y points down

        // 3. Pinhole → pixel coordinates.
        let fx = intrinsics[0][0]; let fy = intrinsics[1][1]
        let cx = intrinsics[2][0]; let cy = intrinsics[2][1]
        let u = (fx * x + cx) / Float(imageSize.width)
        let v = (fy * y + cy) / Float(imageSize.height)
        let norm = CGPoint(x: CGFloat(u), y: CGFloat(v))   // [0,1] in image space

        // 4. Normalised image space → viewport, accounting for orientation/aspect.
        let t = displayTransform(imageSize: imageSize, viewport: viewport, orientation: orientation)
        let mapped = norm.applying(t)                        // [0,1] in viewport space
        return CGPoint(x: mapped.x * viewport.width, y: mapped.y * viewport.height)
    }

    /// Maps a [0,1]×[0,1] camera-image point to a [0,1]×[0,1] viewport point for
    /// a portrait-locked phone (image is landscape, so it rotates + letterboxes).
    static func displayTransform(imageSize: CGSize, viewport: CGSize,
                                 orientation: UIInterfaceOrientation) -> CGAffineTransform {
        let imageAspect = imageSize.width / imageSize.height
        let viewAspect  = viewport.width / viewport.height
        var scale: CGFloat = 1
        var tx: CGFloat = 0, ty: CGFloat = 0
        if imageAspect > viewAspect {
            // Image wider than view: fit width, letterbox vertically.
            scale = 1 / imageAspect
            ty = (1 - scale) * 0.5
        } else {
            scale = 1
            tx = 0
        }
        let base = CGAffineTransform(scaleX: scale, y: scale).concatenating(
            CGAffineTransform(translationX: tx, y: ty))
        switch orientation {
        case .portrait, .unknown:
            // Rotate 90° clockwise: (u,v) → (1 - v, u) within the unit square.
            return CGAffineTransform(translationX: 1, y: 0)
                .concatenating(CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 0, ty: 0))
                .concatenating(base)
        default:
            return base
        }
    }
    #endif

    // MARK: - Viewport projection (orientation-source agnostic)

    /// Projects a start-frame direction onto the viewport, given the current
    /// camera look direction + an up hint. Works for both CoreMotion and ARKit
    /// paths since everything is expressed in the session start frame.
    /// Returns `(nil, 0)` when the direction is behind the camera.
    public static func projectOnViewport(pointDir: SIMD3<Float>,
                                         lookDir: SIMD3<Float>,
                                         upHint: SIMD3<Float>,
                                         horizontalFOV: Double,
                                         viewport: CGSize) -> (position: CGPoint?, scale: CGFloat) {
        let fwd = simd_normalize(lookDir)
        var right = simd_cross(fwd, simd_normalize(upHint))
        if simd_length(right) < 1e-4 { right = SIMD3<Float>(1, 0, 0) }
        right = simd_normalize(right)
        let up = simd_cross(right, fwd)

        let z = simd_dot(pointDir, fwd)
        guard z > 1e-3 else { return (nil, 0) }

        let x = simd_dot(pointDir, right) / z
        let y = simd_dot(pointDir, up) / z

        let halfFov = tan(horizontalFOV / 2)
        let f = Double(viewport.width / 2) / halfFov
        let sx = Double(viewport.width) / 2 + f * Double(x)
        let sy = Double(viewport.height) / 2 - f * Double(y)

        let radial = sqrt(x * x + y * y)
        let scale = max(0.55, 1.25 - Double(radial) * 0.25)
        return (CGPoint(x: sx, y: sy), CGFloat(scale))
    }

    /// Variant of `projectOnViewport` whose FOV convention **mirrors the panorama
    /// renderer** (`viewer_vertex` in `Shaders.metal`), where `fovRadians` is the
    /// VERTICAL field of view, `f = 1/tan(vfov/2)`, and the horizontal axis is
    /// scaled by `1/aspect`. Use this for any overlay that must stay glued to a
    /// texel on the Metal sphere (tour hotspots) — the `horizontalFOV` overload
    /// above is correct for the capture guide (a real horizontal FOV) but drifts
    /// radially toward centre on portrait screens when fed the viewer's vertical
    /// FOV. Returns `(nil, 0)` when the direction is behind the camera.
    public static func projectOnViewport(pointDir: SIMD3<Float>,
                                         lookDir: SIMD3<Float>,
                                         upHint: SIMD3<Float>,
                                         verticalFOV: Double,
                                         aspect: Double,
                                         viewport: CGSize) -> (position: CGPoint?, scale: CGFloat) {
        let fwd = simd_normalize(lookDir)
        var right = simd_cross(fwd, simd_normalize(upHint))
        if simd_length(right) < 1e-4 { right = SIMD3<Float>(1, 0, 0) }
        right = simd_normalize(right)
        let up = simd_cross(right, fwd)

        let z = simd_dot(pointDir, fwd)
        guard z > 1e-3 else { return (nil, 0) }

        let x = simd_dot(pointDir, right) / z
        let y = simd_dot(pointDir, up) / z

        // Mirrors viewer_vertex: f = 1/tan(vfov/2); horizontal extent ÷ aspect,
        // vertical extent plain — so the marker lands on the same screen point as
        // the panorama texel beneath it at any viewport aspect.
        let f = 1.0 / tan(verticalFOV / 2)
        let halfW = Double(viewport.width) / 2
        let halfH = Double(viewport.height) / 2
        let sx = halfW + halfW * Double(x) * f / aspect
        let sy = halfH - halfH * Double(y) * f

        let radial = sqrt(x * x + y * y)
        let scale = max(0.55, 1.25 - Double(radial) * 0.25)
        return (CGPoint(x: sx, y: sy), CGFloat(scale))
    }

    // MARK: - Yaw helpers

    /// Wraps an angle to (-π, π].
    public static func wrap(_ angle: Double) -> Double {
        var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if a <= -.pi { a += 2 * .pi }
        if a > .pi { a -= 2 * .pi }
        return a
    }
}

// MARK: - Clamped (FloatingPoint only, to avoid Comparable/FloatingPoint ambiguity)

public extension FloatingPoint {
    @inlinable
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// Swift SIMD has no `.xyz` swizzle — keep call sites readable.
@inlinable
public func simd_xyz(_ v: SIMD4<Float>) -> SIMD3<Float> {
    SIMD3<Float>(v.x, v.y, v.z)
}
