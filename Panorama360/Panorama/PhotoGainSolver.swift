import Foundation
import Metal
import MetalKit
import ImageIO
import simd

/// Global per-channel gain compensation (Brown & Lowe style), measured in
/// equirectangular space.
///
/// The camera re-meters and re-white-balances between shots, so a raw stitch
/// looks like a patchwork of slightly different photos. Matching each photo to
/// the session mean (what `ExposureCompensator` does) cannot fix it, because two
/// photos of the same wall legitimately have different means when one of them
/// also sees a window.
///
/// Instead every photo is projected into a tiny equirect **probe**: two probes
/// then share pixel coordinates exactly when they see the same direction, so the
/// mean colour over that shared region is directly comparable. Solving all
/// pairwise constraints at once yields one gain per photo per channel that makes
/// every overlap agree — which fixes brightness and colour cast in one pass.
public final class PhotoGainSolver {

    public struct Options: Sendable {
        /// Probe resolution. Small on purpose: only region means are needed.
        public var probeWidth: Int
        public var probeHeight: Int
        /// Photos are decoded at thumbnail size for probing (~10× faster).
        public var thumbnailMaxPixel: Int
        public var iterations: Int
        public var minGain: Float
        public var maxGain: Float
        /// Pairs sharing fewer probe pixels than this are too noisy to trust.
        public var minOverlapPixels: Int

        public init(probeWidth: Int = 128,
                    probeHeight: Int = 64,
                    thumbnailMaxPixel: Int = 384,
                    iterations: Int = 40,
                    minGain: Float = 0.55,
                    maxGain: Float = 1.85,
                    minOverlapPixels: Int = 24) {
            self.probeWidth = probeWidth
            self.probeHeight = probeHeight
            self.thumbnailMaxPixel = thumbnailMaxPixel
            self.iterations = iterations
            self.minGain = minGain
            self.maxGain = maxGain
            self.minOverlapPixels = minOverlapPixels
        }
    }

    private struct Probe {
        /// Mean colour per probe pixel, already divided by its weight.
        var rgb: [Float]      // 3 per pixel
        var mask: [Float]     // coverage weight, 0 where the photo does not see it
        var forward: SIMD3<Float>
        var halfFOV: Float
    }

    private struct Pair {
        var i: Int
        var j: Int
        var count: Float
        var meanI: SIMD3<Float>
        var meanJ: SIMD3<Float>
    }

    private let options: Options
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let textureLoader: MTKTextureLoader
    private let probeTexture: MTLTexture

    public init(device: MTLDevice, commandQueue: MTLCommandQueue, options: Options = Options()) throws {
        self.options = options
        self.device = device
        self.commandQueue = commandQueue

        guard let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "quad_vertex"),
              let fragment = library.makeFunction(name: "accumulate_fragment") else {
            throw StitchError.metalUnavailable
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertex
        desc.fragmentFunction = fragment
        desc.colorAttachments[0].pixelFormat = .rgba32Float
        pipeline = try device.makeRenderPipelineState(descriptor: desc)

        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDesc) else {
            throw StitchError.renderFailed
        }
        self.sampler = sampler
        self.textureLoader = MTKTextureLoader(device: device)

        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float,
            width: options.probeWidth, height: options.probeHeight, mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: texDesc) else {
            throw StitchError.renderFailed
        }
        probeTexture = texture
    }

    /// One RGB gain per sample, or `nil` when the photos do not overlap enough
    /// to constrain a solve (caller should fall back to `ExposureCompensator`).
    public func gains(for samples: [CaptureSample],
                      onProgress: (Double) -> Void = { _ in }) -> [SIMD3<Float>]? {
        guard samples.count > 1 else { return nil }

        var probes: [Probe] = []
        probes.reserveCapacity(samples.count)
        for (index, sample) in samples.enumerated() {
            autoreleasepool {
                if let probe = makeProbe(for: sample) { probes.append(probe) }
            }
            onProgress(Double(index + 1) / Double(samples.count))
        }
        guard probes.count == samples.count else {
            Log.stitch.warning("Gain solve aborted — \(samples.count - probes.count, privacy: .public) probes failed")
            return nil
        }

        let pairs = overlaps(in: probes)
        guard !pairs.isEmpty else {
            Log.stitch.info("Gain solve found no usable overlap")
            return nil
        }

        var gains = [SIMD3<Float>](repeating: SIMD3<Float>(repeating: 1), count: probes.count)
        for channel in 0..<3 {
            let solved = solve(channel: channel, pairs: pairs, count: probes.count)
            for i in 0..<probes.count { gains[i][channel] = solved[i] }
        }
        Log.stitch.info("Gain solve: \(pairs.count, privacy: .public) overlapping pairs")
        return gains
    }

    // MARK: - Probing

    private func makeProbe(for sample: CaptureSample) -> Probe? {
        guard let cg = Self.thumbnail(sample.imageURL, maxPixel: options.thumbnailMaxPixel),
              let texture = try? textureLoader.newTexture(
                cgImage: cg,
                options: [.origin: MTKTextureLoader.Origin.topLeft,
                          .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue)]),
              let buffer = commandQueue.makeCommandBuffer() else { return nil }

        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = probeTexture
        desc.colorAttachments[0].loadAction = .clear
        desc.colorAttachments[0].storeAction = .store
        desc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: desc) else { return nil }

        var uniforms = ProjectorUniforms()
        uniforms.quaternion = sample.quaternion.vector
        uniforms.intrinsics = SIMD4<Float>(sample.intrinsics.fx, sample.intrinsics.fy,
                                           sample.intrinsics.cx, sample.intrinsics.cy)
        uniforms.imageSize = SIMD2<Float>(Float(sample.width), Float(sample.height))
        uniforms.outputSize = SIMD2<Float>(Float(options.probeWidth), Float(options.probeHeight))
        uniforms.gain = SIMD4<Float>(1, 1, 1, 1)
        uniforms.feather = 0    // measure the whole frame, not a feathered core

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ProjectorUniforms>.size, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()

        return readProbe(sample: sample)
    }

    private func readProbe(sample: CaptureSample) -> Probe {
        let pixels = options.probeWidth * options.probeHeight
        var raw = [Float](repeating: 0, count: pixels * 4)
        raw.withUnsafeMutableBytes { bytes in
            probeTexture.getBytes(bytes.baseAddress!,
                                  bytesPerRow: options.probeWidth * 4 * MemoryLayout<Float>.size,
                                  from: MTLRegionMake2D(0, 0, options.probeWidth, options.probeHeight),
                                  mipmapLevel: 0)
        }

        var rgb = [Float](repeating: 0, count: pixels * 3)
        var mask = [Float](repeating: 0, count: pixels)
        for p in 0..<pixels {
            let weight = raw[p * 4 + 3]
            guard weight > 1e-4 else { continue }
            mask[p] = weight
            rgb[p * 3 + 0] = raw[p * 4 + 0] / weight
            rgb[p * 3 + 1] = raw[p * 4 + 1] / weight
            rgb[p * 3 + 2] = raw[p * 4 + 2] / weight
        }

        let forward = sample.quaternion.act(SIMD3<Float>(0, 0, -1))
        return Probe(rgb: rgb, mask: mask, forward: forward, halfFOV: Self.halfFOV(of: sample))
    }

    // MARK: - Overlaps

    private func overlaps(in probes: [Probe]) -> [Pair] {
        var pairs: [Pair] = []
        let threshold: Float = 0.05
        for i in 0..<probes.count {
            for j in (i + 1)..<probes.count {
                // Cheap rejection: photos whose optical axes diverge by more
                // than the sum of their half-FOVs cannot share a pixel.
                let angle = acos(min(max(simd_dot(probes[i].forward, probes[j].forward), -1), 1))
                if angle > probes[i].halfFOV + probes[j].halfFOV { continue }

                var sumI = SIMD3<Float>.zero
                var sumJ = SIMD3<Float>.zero
                var count = 0
                let a = probes[i], b = probes[j]
                for p in 0..<a.mask.count where a.mask[p] > threshold && b.mask[p] > threshold {
                    sumI += SIMD3<Float>(a.rgb[p * 3], a.rgb[p * 3 + 1], a.rgb[p * 3 + 2])
                    sumJ += SIMD3<Float>(b.rgb[p * 3], b.rgb[p * 3 + 1], b.rgb[p * 3 + 2])
                    count += 1
                }
                guard count >= options.minOverlapPixels else { continue }
                let n = Float(count)
                pairs.append(Pair(i: i, j: j, count: n, meanI: sumI / n, meanJ: sumJ / n))
            }
        }
        return pairs
    }

    // MARK: - Least-squares solve (Gauss–Seidel on log gains)

    /// Minimises Σ nᵢⱼ · (xᵢ + log Iᵢⱼ − xⱼ − log Iⱼᵢ)² where x is the log gain,
    /// then re-centres so the mean gain stays 1 (correct the mismatch, do not
    /// drift the overall exposure).
    private func solve(channel: Int, pairs: [Pair], count: Int) -> [Float] {
        var incident = [[Int]](repeating: [], count: count)
        for (index, pair) in pairs.enumerated() {
            incident[pair.i].append(index)
            incident[pair.j].append(index)
        }

        var logMeanI = [Float](repeating: 0, count: pairs.count)
        var logMeanJ = [Float](repeating: 0, count: pairs.count)
        for (index, pair) in pairs.enumerated() {
            logMeanI[index] = log(max(pair.meanI[channel], 1e-3))
            logMeanJ[index] = log(max(pair.meanJ[channel], 1e-3))
        }

        var x = [Float](repeating: 0, count: count)
        for _ in 0..<options.iterations {
            for i in 0..<count {
                var numerator: Float = 0
                var denominator: Float = 0
                for index in incident[i] {
                    let pair = pairs[index]
                    let isI = pair.i == i
                    let other = isI ? pair.j : pair.i
                    let mine = isI ? logMeanI[index] : logMeanJ[index]
                    let theirs = isI ? logMeanJ[index] : logMeanI[index]
                    numerator += pair.count * (x[other] + theirs - mine)
                    denominator += pair.count
                }
                guard denominator > 0 else { continue }
                x[i] = numerator / denominator
            }
        }

        let mean = x.reduce(0, +) / Float(count)
        return x.map { min(max(exp($0 - mean), options.minGain), options.maxGain) }
    }

    // MARK: - Helpers

    /// Half of the diagonal field of view, from the photo's own intrinsics.
    private static func halfFOV(of sample: CaptureSample) -> Float {
        let fx = sample.intrinsics.fx
        guard fx > 1 else { return .pi }   // unknown intrinsics → never reject
        let halfDiagonal = (Float(sample.width) * Float(sample.width)
                            + Float(sample.height) * Float(sample.height)).squareRoot() / 2
        return atan(halfDiagonal / fx)
    }

    private static func thumbnail(_ url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
