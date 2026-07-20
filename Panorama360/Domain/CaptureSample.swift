import Foundation
import simd

/// Pinhole camera intrinsics + lens distortion for one captured photo.
/// Distilled to primitives so the type stays `Codable` (simd types are not).
public struct CameraIntrinsics: Codable, Equatable, Sendable {
    public let fx, fy: Float   // focal length in pixels
    public let cx, cy: Float   // principal point in pixels
    /// Brown–Conrady radial distortion coefficients (best-effort; ARKit does
    /// not expose them directly, so these default to 0 and may be refined).
    public let k1, k2: Float
    /// Third radial coefficient (refines the periphery). Defaults to 0; decoded
    /// from old archives as 0 when the key is absent (see `init(from:)`).
    public let k3: Float

    public init(fx: Float, fy: Float, cx: Float, cy: Float, k1: Float = 0, k2: Float = 0, k3: Float = 0) {
        self.fx = fx; self.fy = fy
        self.cx = cx; self.cy = cy
        self.k1 = k1; self.k2 = k2; self.k3 = k3
    }

    public static let zero = CameraIntrinsics(fx: 0, fy: 0, cx: 0, cy: 0)

    private enum CodingKeys: String, CodingKey { case fx, fy, cx, cy, k1, k2, k3 }

    /// Custom decode so archives written before k1/k2/k3 (or before k3) still
    /// load — missing keys default to 0 instead of throwing.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fx = try c.decode(Float.self, forKey: .fx)
        fy = try c.decode(Float.self, forKey: .fy)
        cx = try c.decode(Float.self, forKey: .cx)
        cy = try c.decode(Float.self, forKey: .cy)
        k1 = try c.decodeIfPresent(Float.self, forKey: .k1) ?? 0
        k2 = try c.decodeIfPresent(Float.self, forKey: .k2) ?? 0
        k3 = try c.decodeIfPresent(Float.self, forKey: .k3) ?? 0
    }
}

/// A captured photo plus the geometry needed to project it onto the panorama sphere.
public struct CaptureSample: Identifiable, Codable, Sendable {
    public let id: UUID
    public let imageURL: URL
    public let width: Int
    public let height: Int
    public let intrinsics: CameraIntrinsics

    /// Orientation of this shot **relative to the reference (first) shot**,
    /// as a unit quaternion (ix, iy, iz, real). The stitcher rotates a sphere
    /// direction into this photo's frame using it.
    public let qx, qy, qz, qw: Float

    /// Absolute device orientation at capture (radians) — diagnostics only.
    public let pitch: Double
    public let yaw: Double

    /// EXIF orientation of the stored HEIC (see CGImagePropertyOrientation).
    public let exifOrientation: Int
    public let timestamp: Double

    public init(id: UUID = UUID(),
                imageURL: URL,
                width: Int, height: Int,
                intrinsics: CameraIntrinsics,
                quaternion: simd_quatf,
                pitch: Double, yaw: Double,
                exifOrientation: Int,
                timestamp: Double) {
        self.id = id
        self.imageURL = imageURL
        self.width = width
        self.height = height
        self.intrinsics = intrinsics
        self.qx = quaternion.vector.x
        self.qy = quaternion.vector.y
        self.qz = quaternion.vector.z
        self.qw = quaternion.vector.w
        self.pitch = pitch
        self.yaw = yaw
        self.exifOrientation = exifOrientation
        self.timestamp = timestamp
    }

    /// Reconstruct the relative rotation quaternion for the stitcher.
    public var quaternion: simd_quatf {
        simd_quatf(ix: qx, iy: qy, iz: qz, r: qw)
    }
}
