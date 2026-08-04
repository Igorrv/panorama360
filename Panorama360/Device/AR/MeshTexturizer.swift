import ARKit
import CoreVideo
import simd

/// Projects the camera's `ARFrame.capturedImage` colour onto LiDAR mesh vertices,
/// accumulating a per-vertex RGBA8 colour over the scan. This is the "photo → 3D"
/// step that turns the grey LiDAR mesh into a photoreal, navigable space —
/// entirely on-device, no backend.
///
/// Keyed by `(anchorIdentifier, localVertexIndex)` so refined `ARMeshAnchor`
/// updates overwrite the same vertex instead of duplicating. `accumulate(frame:)`
/// is meant to be called from the `RoomScanViewModel` poll loop (~3×/s): it skips
/// anchors that have barely moved since the last sample.
public final class MeshTexturizer {

    /// Running weighted colour sum per vertex (premultiplied by `w`).
    private struct Accumulator {
        var r: Float = 0
        var g: Float = 0
        var b: Float = 0
        var w: Float = 0
    }

    private var byAnchor: [UUID: [Accumulator]] = [:]
    private var lastTransform: [UUID: simd_float4x4] = [:]

    /// Below this total weight a vertex counts as uncoloured (coverage + white fill).
    private let minWeight: Float = 0.25
    /// Depth-consistency margin (metres). Sample is rejected if a closer surface is
    /// this much in front of the vertex.
    private let occlusionMargin: Float = 0.06
    /// Laplacian-variance floor; frames blurrier than this are skipped wholesale.
    private let blurFloor: Float = 80
    /// Translation jitter (m) below which an anchor is considered unchanged.
    private let moveEpsilon: Float = 0.01

    public init() {}

    public func reset() {
        byAnchor.removeAll()
        lastTransform.removeAll()
    }

    /// Fraction (0…1) of known vertices that have accumulated enough colour.
    public func coverage() -> Float {
        var total = 0
        var covered = 0
        for (_, acc) in byAnchor {
            total += acc.count
            covered += acc.reduce(0) { $0 + ($1.w >= minWeight ? 1 : 0) }
        }
        return total == 0 ? 0 : Float(covered) / Float(total)
    }

    /// Finalized RGBA8 colour per local vertex for an anchor, or nil if never seen.
    /// Uncoloured vertices fall back to opaque white.
    public func colors(for anchorID: UUID) -> [SIMD4<UInt8>]? {
        guard let acc = byAnchor[anchorID] else { return nil }
        return acc.map {
            if $0.w < minWeight { return SIMD4<UInt8>(255, 255, 255, 255) }
            let r = simd_clamp($0.r / $0.w, 0, 1)
            let g = simd_clamp($0.g / $0.w, 0, 1)
            let b = simd_clamp($0.b / $0.w, 0, 1)
            return SIMD4<UInt8>(UInt8(r * 255), UInt8(g * 255), UInt8(b * 255), 255)
        }
    }

    // MARK: - Accumulation

    public func accumulate(frame: ARFrame) {
        let cam = frame.camera
        let view = simd_inverse(cam.transform)   // world → camera (ARKit camera looks along −Z)
        let K = cam.intrinsics
        let fx = K[0][0]; let fy = K[1][1]
        let cx = K[2][0]; let cy = K[2][1]
        let imgW = Int(cam.imageResolution.width)
        let imgH = Int(cam.imageResolution.height)
        guard imgW > 0, imgH > 0 else { return }

        guard let yuv = YUVPlanes(pixelBuffer: frame.capturedImage) else { return }
        CVPixelBufferLockBaseAddress(frame.capturedImage, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(frame.capturedImage, .readOnly) }

        // Whole-frame blur gate on the luma plane.
        guard laplacianVariance(yuv, width: imgW, height: imgH) >= blurFloor else { return }

        // Optional LiDAR depth for occlusion rejection.
        let depth = DepthMap(pixelBuffer: frame.sceneDepth?.depthMap,
                             imgWidth: imgW, imgHeight: imgH)
        if let pb = frame.sceneDepth?.depthMap {
            CVPixelBufferLockBaseAddress(pb, .readOnly)
        }
        defer {
            if let pb = frame.sceneDepth?.depthMap {
                CVPixelBufferUnlockBaseAddress(pb, .readOnly)
            }
        }

        let halfDiag = Float(max(imgW, imgH)) * 0.5

        for case let mesh as ARMeshAnchor in frame.anchors {
            let id = mesh.identifier
            // Skip anchors that have barely moved since last sample (cost bound).
            if let prev = lastTransform[id] {
                let dt = simd_distance(prev.columns.3.xyz, mesh.transform.columns.3.xyz)
                if dt < moveEpsilon { continue }
            }
            lastTransform[id] = mesh.transform

            let verts = readVertices(mesh.geometry.vertices)
            let vc = verts.count / 3
            guard vc > 0 else { continue }
            if byAnchor[id]?.count != vc {
                byAnchor[id] = Array(repeating: Accumulator(), count: vc)
            }
            guard var acc = byAnchor[id] else { continue }

            let T = mesh.transform   // anchor-local → world
            for i in 0..<vc {
                let lp = SIMD3<Float>(verts[i * 3], verts[i * 3 + 1], verts[i * 3 + 2])
                let wp = (T * SIMD4<Float>(lp, 1)).xyz
                let cp = (view * SIMD4<Float>(wp, 1)).xyz
                let d = -cp.z                      // depth along camera forward (m, >0 in front)
                guard d > 0.1, d < 12 else { continue }

                let u = fx * cp.x / d + cx
                let v = fy * cp.y / d + cy
                guard u >= 0, u <= Float(imgW - 1), v >= 0, v <= Float(imgH - 1) else { continue }

                // Occlusion: if the depth pixel in front of this vertex is closer,
                // the vertex is behind an object — reject the colour sample.
                if let depth {
                    if let sd = depth.sample(col: u, row: v), sd < d - occlusionMargin {
                        continue
                    }
                }

                let rgb = yuv.sample(col: u, row: v, width: imgW, height: imgH)

                // Weighting: centre of frame × proximity (closer = sharper).
                let centre = 1.0 - 0.6 * min(1.0, hypot(u - cx, v - cy) / halfDiag)
                let proximity = 1.0 / (1.0 + d * d * 0.5)
                let w = centre * proximity

                acc[i].r += rgb.x * w
                acc[i].g += rgb.y * w
                acc[i].b += rgb.z * w
                acc[i].w += w
            }
            byAnchor[id] = acc
        }
    }

    // MARK: - Geometry source reader (mirrors RoomScanner's Metal pointer read)

    private func readVertices(_ s: ARMeshAnchor.Geometry.Source) -> [Float] {
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

    // MARK: - Blur estimate (luma Laplacian variance)

    private func laplacianVariance(_ yuv: YUVPlanes, width: Int, height: Int) -> Float {
        guard let y = yuv.yBase else { return .greatestFiniteMagnitude }
        let rowStride = yuv.yStride
        let step = 6
        var sum: Float = 0
        var sumSq: Float = 0
        var n = 0
        for row in stride(from: 1, to: height - 1, by: step) {
            for col in stride(from: 1, to: width - 1, by: step) {
                let c = Float(y[row * rowStride + col])
                let l = Float(y[row * rowStride + col - 1])
                let r = Float(y[row * rowStride + col + 1])
                let u = Float(y[(row - 1) * rowStride + col])
                let d = Float(y[(row + 1) * rowStride + col])
                let lap = 4 * c - l - r - u - d
                sum += lap
                sumSq += lap * lap
                n += 1
            }
        }
        guard n > 0 else { return .greatestFiniteMagnitude }
        let mean = sum / Float(n)
        return sumSq / Float(n) - mean * mean
    }
}

// MARK: - YUV 4:2:0 biplanar sampler

private struct YUVPlanes {
    let yBase: UnsafePointer<UInt8>?
    let yStride: Int
    let cbcrBase: UnsafePointer<UInt8>?
    let cbcrStride: Int
    let fullRange: Bool

    init?(pixelBuffer: CVPixelBuffer) {
        let fmt = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard fmt == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
              fmt == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange else { return nil }
        fullRange = (fmt == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        yStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        cbcrStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        yBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)?.assumingMemoryBound(to: UInt8.self)
        cbcrBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)?.assumingMemoryBound(to: UInt8.self)
    }

    /// Nearest-neighbour YCbCr → linear RGB (BT.601), returns 0…1.
    func sample(col: Float, row: Float, width: Int, height: Int) -> SIMD3<Float> {
        guard let y = yBase else { return SIMD3(0.5, 0.5, 0.5) }
        let ui = max(0, min(width - 1, Int(col)))
        let vi = max(0, min(height - 1, Int(row)))
        var yf = Float(y[vi * yStride + ui])
        guard let cbcr = cbcrBase else { return SIMD3(repeating: yf / 255) }
        let cu = ui / 2
        let cv = vi / 2
        var cb = Float(cbcr[cv * cbcrStride + cu * 2]) - 128
        var cr = Float(cbcr[cv * cbcrStride + cu * 2 + 1]) - 128
        if !fullRange {
            yf = (yf - 16) * 255 / 219
            cb *= 255 / 224
            cr *= 255 / 224
        }
        let r = (yf + 1.402 * cr) / 255
        let g = (yf - 0.344 * cb - 0.714 * cr) / 255
        let b = (yf + 1.772 * cb) / 255
        return SIMD3(simd_clamp(r, 0, 1), simd_clamp(g, 0, 1), simd_clamp(b, 0, 1))
    }
}

// MARK: - LiDAR depth map wrapper

private struct DepthMap {
    let base: UnsafePointer<Float>?
    let stride: Int   // floats per row
    let width: Int
    let height: Int
    let sx: Float     // image-pixel → depth-pixel scale X
    let sy: Float     // image-pixel → depth-pixel scale Y

    init?(pixelBuffer: CVPixelBuffer?, imgWidth: Int, imgHeight: Int) {
        guard let pb = pixelBuffer else { return nil }
        width = CVPixelBufferGetWidth(pb)
        height = CVPixelBufferGetHeight(pb)
        stride = CVPixelBufferGetBytesPerRow(pb) / MemoryLayout<Float>.stride
        base = CVPixelBufferGetBaseAddress(pb)?.assumingMemoryBound(to: Float.self)
        // Depth map is lower-res than the captured image but is aligned to it.
        sx = Float(width) / Float(max(1, imgWidth))
        sy = Float(height) / Float(max(1, imgHeight))
    }

    func sample(col: Float, row: Float) -> Float? {
        guard let base else { return nil }
        let c = max(0, min(width - 1, Int(col * sx)))
        let r = max(0, min(height - 1, Int(row * sy)))
        return base[r * stride + c]
    }
}
