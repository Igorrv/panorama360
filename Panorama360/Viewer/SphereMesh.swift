import Foundation
import simd

/// Generates the inside-out UV sphere used by the 360° viewer.
///
/// Vertex positions use the **same spherical convention as the panorama**:
/// `(pitch=0, yaw=0) → (0, 0, −1)`, so a vertex's normalised position is exactly
/// the direction needed to sample the equirectangular texture.
public enum SphereMesh {

    /// Triangle vertex positions (unit radius) for the viewer sphere.
    public static func positions(rings: Int = 48, segments: Int = 96) -> [SIMD3<Float>] {
        var verts: [SIMD3<Float>] = []
        verts.reserveCapacity(rings * segments * 6)

        func point(_ lat: Float, _ lon: Float) -> SIMD3<Float> {
            let cp = cos(lat)
            return SIMD3<Float>(-sin(lon) * cp, sin(lat), -cos(lon) * cp)
        }

        for r in 0..<rings {
            let lat0 = Float.pi * (-0.5 + Float(r) / Float(rings))
            let lat1 = Float.pi * (-0.5 + Float(r + 1) / Float(rings))
            for s in 0..<segments {
                let lon0 = 2 * Float.pi * Float(s) / Float(segments)
                let lon1 = 2 * Float.pi * Float(s + 1) / Float(segments)
                let a = point(lat0, lon0)
                let b = point(lat1, lon0)
                let c = point(lat1, lon1)
                let d = point(lat0, lon1)
                verts.append(contentsOf: [a, b, d, b, c, d])
            }
        }
        return verts
    }

    /// Same data as a contiguous `Data` buffer for `makeBuffer`.
    public static func positionsData(rings: Int = 48, segments: Int = 96) -> Data {
        var array = positions(rings: rings, segments: segments)
        return Data(bytes: &array, count: array.count * MemoryLayout<SIMD3<Float>>.size)
    }
}
