import ARKit
import Metal
import simd

/// Collects LiDAR `ARMeshAnchor`s seen during a world-tracking scan and merges
/// them into one world-space `RoomMesh`. **LiDAR only** — gate the entry point on
/// `RoomScanner.isSupported`. RealityKit renders the live anchors in the `ARView`
/// (it owns the session delegate, so we do NOT install one — we poll
/// `currentFrame.anchors` instead and upsert them here). On finish, `merged()`
/// snapshots every collected anchor's geometry into a single mesh.
public final class RoomScanner {

    /// Latest mesh anchor per identifier (newer updates overwrite older ones).
    public private(set) var anchors: [UUID: ARMeshAnchor] = [:]
    /// Total faces above which `merged()` stride-samples triangles (anti-OOM).
    public static let maxFaces = 400_000

    public init() {}

    public var anchorCount: Int { anchors.count }

    public static var isSupported: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    /// Configuration with scene reconstruction (meshing). Nil on non-LiDAR.
    public static func makeConfiguration() -> ARWorldTrackingConfiguration? {
        guard isSupported else { return nil }
        let config = ARWorldTrackingConfiguration()
        config.sceneReconstruction = .mesh
        config.worldAlignment = .gravity
        config.planeDetection = []
        // Per-frame depth map (LiDAR) — used by `MeshTexturizer` for occlusion
        // rejection. Safe no-op on configurations that already expose it.
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        return config
    }

    // MARK: - Anchor ingestion (called by the polling view-model)

    public func ingest(_ anchors: [ARAnchor]) {
        for a in anchors where a is ARMeshAnchor { upsert(a) }
    }

    public func upsert(_ anchor: ARAnchor) {
        guard let mesh = anchor as? ARMeshAnchor else { return }
        anchors[mesh.identifier] = mesh
    }

    // MARK: - Merge

    /// Snapshots all collected anchors into one world-space `RoomMesh`. Positions
    /// are transformed by each anchor's transform; normals by its rotation.
    /// Faces are stride-sampled when the total exceeds `maxFaces`.
    public func merged() -> RoomMesh? { merged(using: nil) }

    /// Same merge as `merged()`, additionally baking per-vertex RGBA8 colour from
    /// `MeshTexturizer` (same iteration order ⇒ colours align 1:1 with merged
    /// vertices). Vertices without accumulated colour fall back to opaque white.
    public func merged(using texturizer: MeshTexturizer?) -> RoomMesh? {
        guard !anchors.isEmpty else { return nil }
        var parts: [(part: MeshPart, transform: simd_float4x4, id: UUID)] = []
        var totalFaces = 0
        for anchor in anchors.values {
            guard let part = Self.extract(anchor) else { continue }
            parts.append((part, anchor.transform, anchor.identifier))
            totalFaces += part.faces.count / 3
        }
        guard !parts.isEmpty, totalFaces > 0 else { return nil }
        let stride = max(1, Int((Double(totalFaces) / Double(Self.maxFaces)).rounded(.up)))

        var positions: [Float] = []
        var normals: [Float] = []
        var faces: [UInt32] = []
        var colors: [UInt8] = []
        var vertexOffset: UInt32 = 0

        for item in parts {
            let part = item.part
            let t = item.transform
            let id = item.id
            let rot = simd_float3x3(columns: (simd_xyz(t.columns.0), simd_xyz(t.columns.1), simd_xyz(t.columns.2)))
            let vc = part.positions.count / 3
            positions.reserveCapacity(positions.count + vc * 3)
            for i in 0..<vc {
                let p = SIMD3<Float>(part.positions[i * 3], part.positions[i * 3 + 1], part.positions[i * 3 + 2])
                let wp = simd_xyz(t * SIMD4<Float>(p, 1))
                positions.append(wp.x); positions.append(wp.y); positions.append(wp.z)
            }
            if part.normals.count == part.positions.count {
                normals.reserveCapacity(normals.count + vc * 3)
                for i in 0..<vc {
                    let n = SIMD3<Float>(part.normals[i * 3], part.normals[i * 3 + 1], part.normals[i * 3 + 2])
                    let wn = simd_normalize(rot * n)
                    normals.append(wn.x); normals.append(wn.y); normals.append(wn.z)
                }
            }
            // Keep every stride-th triangle; rebase indices into the merged array.
            var f = 0
            while f * 3 + 2 < part.faces.count {
                faces.append(part.faces[f * 3] + vertexOffset)
                faces.append(part.faces[f * 3 + 1] + vertexOffset)
                faces.append(part.faces[f * 3 + 2] + vertexOffset)
                f += stride
            }
            // Per-vertex colour in the SAME order the vertices were just appended.
            if let texturizer {
                let anchorColors = texturizer.colors(for: id)
                colors.reserveCapacity(colors.count + vc * 4)
                for i in 0..<vc {
                    if let ac = anchorColors, i < ac.count {
                        let c = ac[i]
                        colors.append(c.x); colors.append(c.y); colors.append(c.z); colors.append(c.w)
                    } else {
                        colors.append(255); colors.append(255); colors.append(255); colors.append(255)
                    }
                }
            }
            vertexOffset += UInt32(vc)
        }
        // Normals must be empty or fully populated; partial ⇒ drop (flat shading).
        if normals.count != positions.count { normals = [] }
        return RoomMesh(positions: positions, normals: normals, faces: faces, colors: colors)
    }

    // MARK: - ARMeshAnchor geometry extraction (the riskiest code — see plan)

    private struct MeshPart {
        let positions: [Float]
        let normals: [Float]
        let faces: [UInt32]
    }

    private typealias GeoSource = ARGeometrySource
    private typealias GeoElement = ARGeometryElement

    private static func extract(_ anchor: ARMeshAnchor) -> MeshPart? {
        let g = anchor.geometry
        let positions = readVertices(g.vertices)
        let normals = readVertices(g.normals)
        let faces = readFaces(g.faces)
        guard !positions.isEmpty, !faces.isEmpty else { return nil }
        return MeshPart(positions: positions, normals: normals, faces: faces)
    }

    /// Reads a 3-component vertex source (positions or normals) as flat Floats.
    private static func readVertices(_ s: GeoSource) -> [Float] {
        let n = s.count
        guard n > 0, s.componentsPerVector == 3 else { return [] }
        let base = s.buffer.contents().advanced(by: s.offset)
        let stride = s.stride
        var out = [Float](); out.reserveCapacity(n * 3)
        for i in 0..<n {
            let p = base.advanced(by: i * stride)
            out.append(p.load(as: Float.self))
            out.append(p.advanced(by: 4).load(as: Float.self))
            out.append(p.advanced(by: 8).load(as: Float.self))
        }
        return out
    }

    /// Reads triangle indices, widening UInt16 → UInt32 as needed.
    private static func readFaces(_ e: GeoElement) -> [UInt32] {
        let total = e.count * e.indexCountPerPrimitive
        let bytes = e.bytesPerIndex
        let base = e.buffer.contents()
        var out = [UInt32](); out.reserveCapacity(total)
        for i in 0..<total {
            let p = base.advanced(by: i * bytes)
            out.append(bytes == 4 ? p.load(as: UInt32.self) : UInt32(p.load(as: UInt16.self)))
        }
        return out
    }
}
