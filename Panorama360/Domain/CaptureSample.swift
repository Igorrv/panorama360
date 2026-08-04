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

    /// Gravity direction in the **device** frame at capture, normalised.
    /// All-zero means it was not recorded (old archives / ARKit path before
    /// gravity plumbing), which disables horizon levelling for the session.
    public let gx, gy, gz: Float

    /// EXIF orientation of the stored HEIC (see CGImagePropertyOrientation).
    public let exifOrientation: Int
    public let timestamp: Double

    public init(id: UUID = UUID(),
                imageURL: URL,
                width: Int, height: Int,
                intrinsics: CameraIntrinsics,
                quaternion: simd_quatf,
                pitch: Double, yaw: Double,
                gravity: SIMD3<Double> = .zero,
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
        self.gx = Float(gravity.x)
        self.gy = Float(gravity.y)
        self.gz = Float(gravity.z)
        self.exifOrientation = exifOrientation
        self.timestamp = timestamp
    }

    private enum CodingKeys: String, CodingKey {
        case id, imageURL, width, height, intrinsics
        case qx, qy, qz, qw, pitch, yaw, gx, gy, gz
        case exifOrientation, timestamp
    }

    /// Custom decode so archives written before the gravity fields still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        imageURL = try c.decode(URL.self, forKey: .imageURL)
        width = try c.decode(Int.self, forKey: .width)
        height = try c.decode(Int.self, forKey: .height)
        intrinsics = try c.decode(CameraIntrinsics.self, forKey: .intrinsics)
        qx = try c.decode(Float.self, forKey: .qx)
        qy = try c.decode(Float.self, forKey: .qy)
        qz = try c.decode(Float.self, forKey: .qz)
        qw = try c.decode(Float.self, forKey: .qw)
        pitch = try c.decode(Double.self, forKey: .pitch)
        yaw = try c.decode(Double.self, forKey: .yaw)
        gx = try c.decodeIfPresent(Float.self, forKey: .gx) ?? 0
        gy = try c.decodeIfPresent(Float.self, forKey: .gy) ?? 0
        gz = try c.decodeIfPresent(Float.self, forKey: .gz) ?? 0
        exifOrientation = try c.decode(Int.self, forKey: .exifOrientation)
        timestamp = try c.decode(Double.self, forKey: .timestamp)
    }

    /// Reconstruct the relative rotation quaternion for the stitcher.
    public var quaternion: simd_quatf {
        simd_quatf(ix: qx, iy: qy, iz: qz, r: qw)
    }

    /// Gravity in the device frame (zero when unavailable).
    public var gravity: SIMD3<Float> {
        SIMD3<Float>(gx, gy, gz)
    }
}
