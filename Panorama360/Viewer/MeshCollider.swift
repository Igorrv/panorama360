import simd
import Foundation

/// CPU-side collision against a merged `RoomMesh`. A uniform spatial hash maps
/// each triangle into the grid cells its AABB overlaps, so ray casts only test a
/// handful of nearby triangles. Used by the walk viewer for floor-following
/// (gravity) and wall collision. The mesh is static, so the index is built once.
///
/// Deliberately RealityKit-collision-free: we own the geometry, and a direct
/// ray–triangle test avoids quirks of generated collision shapes on dense meshes.
public struct MeshCollider: Sendable {

    private let positions: [Float]
    private let faces: [UInt32]
    private let cell: Float
    private var grid: [SIMD3<Int>: [Int]] = [:]

    public init(_ mesh: RoomMesh, cellSize: Float = 0.5) {
        positions = mesh.positions
        faces = mesh.faces
        cell = max(0.1, cellSize)
        let triCount = faces.count / 3
        for t in 0..<triCount {
            let a = vertex(faces[t * 3])
            let b = vertex(faces[t * 3 + 1])
            let c = vertex(faces[t * 3 + 2])
            let lo = cellOf(simd_min(simd_min(a, b), c))
            let hi = cellOf(simd_max(simd_max(a, b), c))
            for gx in lo.x...hi.x {
                for gy in lo.y...hi.y {
                    for gz in lo.z...hi.z {
                        grid[SIMD3<Int>(gx, gy, gz), default: []].append(t)
                    }
                }
            }
        }
    }

    /// Highest surface directly under (x, z), searching down `maxDown` metres
    /// from `fromY`. Returns the hit y (where the camera feet should rest).
    public func floorHeight(x: Float, z: Float, fromY: Float, maxDown: Float = 5) -> Float? {
        let origin = SIMD3<Float>(x, fromY, z)
        guard let dist = nearestHit(origin: origin, dir: SIMD3<Float>(0, -1, 0), maxDist: maxDown) else {
            return nil
        }
        return fromY - dist
    }

    /// True if moving from `from` to `to` (planar) would meet a wall within
    /// `radius`. Probes forward at ankle/torso/head heights and ±radius sideways.
    public func isBlocked(from: SIMD3<Float>, to: SIMD3<Float>, radius: Float) -> Bool {
        let dx = to.x - from.x
        let dz = to.z - from.z
        let len = sqrt(dx * dx + dz * dz)
        guard len > 1e-4 else { return false }
        let dir = SIMD3<Float>(dx / len, 0, dz / len)
        let perp = SIMD3<Float>(-dir.z, 0, dir.x)
        let probeDist = len + radius
        let heights: [Float] = [from.y - 1.5, from.y - 0.8, from.y]   // ankle, torso, head
        for h in heights {
            let base = SIMD3<Float>(from.x, h, from.z)
            for offset in [Float(0), radius * 0.6, -radius * 0.6] {
                let o = base + perp * offset
                if nearestHit(origin: o, dir: dir, maxDist: probeDist) != nil {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Ray cast

    /// Nearest triangle hit distance along `dir` (any length; compares as t), or nil.
    private func nearestHit(origin: SIMD3<Float>, dir: SIMD3<Float>, maxDist: Float) -> Float? {
        let end = origin + dir * maxDist
        let lo = cellOf(simd_min(origin, end) - SIMD3<Float>(repeating: cell))
        let hi = cellOf(simd_max(origin, end) + SIMD3<Float>(repeating: cell))
        var seen = Set<Int>()
        var best = maxDist
        var hit = false
        for gx in lo.x...hi.x {
            for gy in lo.y...hi.y {
                for gz in lo.z...hi.z {
                    guard let tris = grid[SIMD3<Int>(gx, gy, gz)] else { continue }
                    for t in tris {
                        if !seen.insert(t).inserted { continue }
                        if let tt = rayTriangle(origin, dir, t), tt < best, tt > 0 {
                            best = tt
                            hit = true
                        }
                    }
                }
            }
        }
        return hit ? best : nil
    }

    /// Möller–Trumbore ray–triangle. Returns positive t along `dir`, or nil.
    private func rayTriangle(_ ro: SIMD3<Float>, _ rd: SIMD3<Float>, _ t: Int) -> Float? {
        let eps: Float = 1e-6
        let a = vertex(faces[t * 3])
        let b = vertex(faces[t * 3 + 1])
        let c = vertex(faces[t * 3 + 2])
        let e1 = b - a
        let e2 = c - a
        let h = simd_cross(rd, e2)
        let det = simd_dot(e1, h)
        guard abs(det) > eps else { return nil }
        let inv = 1 / det
        let s = ro - a
        let u = inv * simd_dot(s, h)
        guard u >= 0, u <= 1 else { return nil }
        let q = simd_cross(s, e1)
        let v = inv * simd_dot(rd, q)
        guard v >= 0, u + v <= 1 else { return nil }
        let tt = inv * simd_dot(e2, q)
        return tt > eps ? tt : nil
    }

    private func vertex(_ i: UInt32) -> SIMD3<Float> {
        let i = Int(i) * 3
        return SIMD3<Float>(positions[i], positions[i + 1], positions[i + 2])
    }

    private func cellOf(_ p: SIMD3<Float>) -> SIMD3<Int> {
        SIMD3<Int>(Int((p.x / cell).rounded(.down)),
                   Int((p.y / cell).rounded(.down)),
                   Int((p.z / cell).rounded(.down)))
    }
}
