import Foundation

/// A merged, world-space triangle mesh of a scanned room, captured from LiDAR
/// `ARMeshAnchor`s. Stored flat (3 floats per vertex, 3 uints per face) so the
/// on-disk layout is unambiguous — no SIMD3 stride/alignment gotchas to get
/// wrong blind. Persisted by `MeshStore` as a compact `.p3dm` binary.
///
/// `colors` (v2) holds optional per-vertex RGBA8 (4 bytes/vertex, sRGB) captured
/// by projecting `ARFrame.capturedImage` onto the geometry in `MeshTexturizer`.
/// Empty ⇒ uncoloured (rendered flat/white). v1 files load with `colors = []`.
public struct RoomMesh: Sendable {
    public var positions: [Float]   // 3 per vertex (x,y,z), world-space.
    public var normals: [Float]     // 3 per vertex (may be empty ⇒ flat shading).
    public var faces: [UInt32]      // 3 per triangle (indices into positions).
    public var colors: [UInt8]      // 4 per vertex (r,g,b,a), sRGB. Empty ⇒ no colour.

    public init(positions: [Float], normals: [Float], faces: [UInt32], colors: [UInt8] = []) {
        self.positions = positions
        self.normals = normals
        self.faces = faces
        self.colors = colors
    }

    public var vertexCount: Int { positions.count / 3 }
    public var faceCount: Int { faces.count / 3 }

    // MARK: - Binary codec (.p3dm)

    /// 4-byte magic + version + counts, then raw positions/normals/faces.
    private static let magic = "P3DM"
    private static let version: UInt32 = 2

    public func encoded() -> Data {
        var d = Data()
        d.append(contentsOf: Array(Self.magic.utf8))
        appendU32(&d, Self.version)
        appendU32(&d, UInt32(vertexCount))
        appendU32(&d, UInt32(faceCount))
        appendArray(&d, positions)
        appendArray(&d, normals)
        appendArray(&d, faces)
        appendArray(&d, colors)   // v2: RGBA8 per vertex. Absent ⇒ legacy reader stops at faces.
        return d
    }

    public init?(data: Data) {
        guard data.count >= 16,
              String(data: data.subdata(in: 0..<4), encoding: .ascii) == Self.magic else { return nil }
        let version = readU32(data, 4)
        let vCount = Int(readU32(data, 8))
        let fCount = Int(readU32(data, 12))
        var off = 16
        guard let pos: [Float] = readArray(data, offset: &off, count: vCount * 3),
              let nrm: [Float] = readArray(data, offset: &off, count: vCount * 3),
              let fac: [UInt32] = readArray(data, offset: &off, count: fCount * 3) else { return nil }
        positions = pos; normals = nrm; faces = fac
        // v2 adds trailing RGBA8 colors; tolerate files that lack them (or v1).
        if version >= 2, let col: [UInt8] = readArray(data, offset: &off, count: vCount * 4) {
            colors = col
        } else {
            colors = []
        }
    }
}

// MARK: - Codec helpers (file-private)

private func appendU32(_ d: inout Data, _ value: UInt32) {
    Swift.withUnsafeBytes(of: value.littleEndian) { d.append(contentsOf: Array($0)) }
}

private func readU32(_ data: Data, _ off: Int) -> UInt32 {
    var v: UInt32 = 0
    data.subdata(in: off..<off + 4).withUnsafeBytes { v = $0.load(as: UInt32.self) }
    return UInt32(littleEndian: v)
}

/// Appends a typed array's raw bytes via the stable `Data(buffer:)` initializer.
private func appendArray<T>(_ d: inout Data, _ array: [T]) {
    guard !array.isEmpty else { return }
    array.withUnsafeBufferPointer { d.append(Data(buffer: $0)) }
}

/// Reads `count` elements of type `T` starting at `offset`, advancing it.
private func readArray<T>(_ data: Data, offset: inout Int, count: Int) -> [T]? {
    let byteCount = count * MemoryLayout<T>.stride
    guard count > 0, offset + byteCount <= data.count else { return count == 0 ? [] : nil }
    let slice = data.subdata(in: offset..<offset + byteCount)
    offset += byteCount
    return slice.withUnsafeBytes { Array($0.bindMemory(to: T.self)) }
}
