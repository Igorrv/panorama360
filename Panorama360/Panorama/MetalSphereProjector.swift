import Foundation
import Metal
import MetalKit
import CoreImage
import os
import simd

/// Primary stitcher. Warps each photo onto an equirectangular canvas by its
/// known ARKit/CoreMotion orientation and accumulates a weighted (exposure‑
/// matched) blend, then writes the result to disk.
///
/// Because every shot's orientation is known, this is a **direct projection** —
/// no feature matching, no homography search — which is far more robust than a
/// blind stitcher. Four stages do the quality work:
///
/// 1. `HorizonLeveler` removes the tilt the reference shot baked into every frame.
/// 2. `PhotoGainSolver` equalises exposure *and* colour cast across all photos.
/// 3. Two accumulation bands (wide + sharp feather) are blended by `BandBlender`.
/// 4. `PoleFiller` dilates colour into whatever the sweep never covered.
public final class MetalSphereProjector: PanoramaStitcher {

    public struct Options: Sendable {
        public var outputWidth: Int
        public var outputHeight: Int
        /// Feather width for the detail band — narrow, so texture stays crisp.
        public var feather: Float
        /// Feather width for the low band — wide, so exposure steps disappear.
        public var broadFeather: Float
        /// Weight exponent for the detail band. Higher concentrates each output
        /// pixel on the single photo that sees it most head-on (no ghosting).
        public var detailPower: Float
        /// Two-band blending. Off falls back to one plain weighted average.
        public var twoBand: Bool
        public var textureOriginTopLeft: Bool // toggle if the result is vertically flipped

        public init(outputWidth: Int = 4096,
                    outputHeight: Int = 2048,
                    feather: Float = 0.06,
                    broadFeather: Float = 0.7,
                    detailPower: Float = 6,
                    twoBand: Bool = true,
                    textureOriginTopLeft: Bool = true) {
            self.outputWidth = outputWidth
            self.outputHeight = outputHeight
            self.feather = feather
            self.broadFeather = broadFeather
            self.detailPower = detailPower
            self.twoBand = twoBand
            self.textureOriginTopLeft = textureOriginTopLeft
        }

        /// Picks the largest output this device can stitch without being
        /// jetsam-killed. Peak use is ≈ 4 full-res RGBA16F textures; half the
        /// remaining budget is left to the rest of the app.
        public static func adaptive() -> Options {
            let available = Double(os_proc_available_memory())
            guard available > 1 else { return Options() }   // unknown → safe default
            func fits(_ width: Int, _ height: Int) -> Bool {
                available > Double(width * height * 8) * 4 * 2
            }
            if fits(6144, 3072) { return Options(outputWidth: 6144, outputHeight: 3072) }
            if fits(4096, 2048) { return Options(outputWidth: 4096, outputHeight: 2048) }
            if fits(3072, 1536) { return Options(outputWidth: 3072, outputHeight: 1536) }
            return Options(outputWidth: 2048, outputHeight: 1024, twoBand: false)
        }
    }

    public let options: Options
    private let ciContext: CIContext

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let library: MTLLibrary
    private let accumulatePipeline: MTLRenderPipelineState
    private let dividePipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let textureLoader: MTKTextureLoader
    /// Lens undistortion pass. Lazily built; an identity profile or the
    /// kill-switch leaves it unused (zero overhead).
    private lazy var undistorter: Undistorter? = try? Undistorter(device: device, commandQueue: commandQueue)
    /// Hole-fill pass for the final equirect (dilates colour into gaps).
    private lazy var poleFiller: PoleFiller? = try? PoleFiller(
        device: device, commandQueue: commandQueue, width: options.outputWidth, height: options.outputHeight)
    /// Global exposure/white-balance solve. Falls back to `ExposureCompensator`.
    private lazy var gainSolver: PhotoGainSolver? = Self.gainSolveDisabled
        ? nil : try? PhotoGainSolver(device: device, commandQueue: commandQueue)
    /// Two-band combiner. Nil disables two-band blending entirely.
    private lazy var blender: BandBlender? = (!options.twoBand || Self.twoBandDisabled)
        ? nil : try? BandBlender(device: device, commandQueue: commandQueue,
                                 width: options.outputWidth, height: options.outputHeight)

    public init(options: Options = Options()) throws {
        self.options = options
        self.ciContext = CIContext(options: [.useSoftwareRenderer: false])

        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else {
            throw StitchError.metalUnavailable
        }
        self.device = device
        self.commandQueue = commandQueue
        self.library = library

        let accumulateVert = library.makeFunction(name: "quad_vertex")!
        let accumulateFrag = library.makeFunction(name: "accumulate_fragment")!
        let divideFrag = library.makeFunction(name: "divide_fragment")!

        accumulatePipeline = try Self.makePipeline(
            device: device, vertex: accumulateVert, fragment: accumulateFrag,
            format: .rgba16Float, blending: true)
        dividePipeline = try Self.makePipeline(
            device: device, vertex: accumulateVert, fragment: divideFrag,
            format: .rgba16Float, blending: false)

        guard let samplerState = Self.makeSampler(device: device) else {
            throw StitchError.renderFailed
        }
        sampler = samplerState
        textureLoader = MTKTextureLoader(device: device)
    }

    // MARK: - PanoramaStitcher

    public func stitch(samples: [CaptureSample],
                       into outputURL: URL,
                       onProgress: @escaping @Sendable (Double, StitchStage) -> Void) async throws -> URL {

        guard !samples.isEmpty else { throw StitchError.noSamples }

        // Stage: loading + horizon levelling (cheap, sensor data only).
        onProgress(0.02, .loading)
        let orientations = HorizonLeveler.leveledOrientations(for: samples)

        // Stage: global exposure + white-balance equalisation.
        onProgress(0.04, .exposure)
        let gains = resolveGains(samples: samples) { fraction in
            onProgress(0.04 + 0.16 * fraction, .exposure)
        }

        // Stage: project + blend on the GPU. Textures are streamed one at a time
        // (see `render`) so peak memory stays bounded.
        onProgress(0.20, .projecting)
        let finalTexture = try render(samples: samples, orientations: orientations, gains: gains,
                                      onProgress: onProgress)

        // Stage: finalize + write. The accumulator holds linear light, so it has
        // to be tagged as such — otherwise Core Image writes those values out as
        // if they were already gamma-encoded and the panorama lands dark.
        onProgress(0.94, .finalizing)
        let workingSpace = CGColorSpace(name: CGColorSpace.linearSRGB) ?? CGColorSpaceCreateDeviceRGB()
        let ciImage = CIImage(mtlTexture: finalTexture, options: [.colorSpace: workingSpace])?
            .transformed(by: CGAffineTransform(scaleX: 1, y: -1))
            .transformed(by: CGAffineTransform(translationX: 0, y: CGFloat(options.outputHeight)))
        guard let ciImage else { throw StitchError.renderFailed }

        try ImageWriter.write(ciImage, to: outputURL, context: ciContext, compressionQuality: 0.9)
        onProgress(1.0, .finalizing)
        return outputURL
    }

    // MARK: - Exposure

    /// Per-channel gains from the pairwise solve, or session-mean luminance
    /// gains when the photos do not overlap enough to constrain it.
    private func resolveGains(samples: [CaptureSample],
                              onProgress: (Double) -> Void) -> [SIMD3<Float>] {
        if let gainSolver, let solved = gainSolver.gains(for: samples, onProgress: onProgress) {
            return solved
        }
        let luminance = ExposureCompensator.gains(for: samples,
                                                 loader: { Self.loadCIImage($0) },
                                                 context: ciContext)
        return luminance.map { SIMD3<Float>(repeating: $0) }
    }

    // MARK: - Rendering

    /// Streams photos one texture at a time inside an autoreleasepool (peak VRAM
    /// ≈ 1 photo + 2 accumulators; loading all up front would be jetsam-killed).
    /// The final equirect is hole-filled at the end.
    private func render(samples: [CaptureSample],
                        orientations: [simd_quatf],
                        gains: [SIMD3<Float>],
                        onProgress: @escaping @Sendable (Double, StitchStage) -> Void) throws -> MTLTexture {

        let width = options.outputWidth, height = options.outputHeight
        let bandBlender = blender
        var accumBroad: MTLTexture? = try makeTexture(width: width, height: height,
                                                      usage: [.shaderRead, .renderTarget])
        var accumDetail: MTLTexture?
        if bandBlender != nil {
            accumDetail = try makeTexture(width: width, height: height,
                                          usage: [.shaderRead, .renderTarget])
        }

        var cleared = false
        let total = max(samples.count, 1)
        var processed = 0

        for (i, sample) in samples.enumerated() {
            try autoreleasepool {
                guard let cg = Self.loadCGImage(sample.imageURL) else {
                    Log.stitch.warning("Skipping unreadable image \(sample.imageURL.lastPathComponent, privacy: .public)")
                    return
                }
                let photo = try makePhotoTexture(cg: cg, sample: sample)

                guard let buffer = commandQueue.makeCommandBuffer() else { throw StitchError.renderFailed }
                let gain = i < gains.count ? gains[i] : SIMD3<Float>(repeating: 1)
                let orientation = i < orientations.count ? orientations[i] : sample.quaternion
                // Clear the accumulators on the first *successfully accumulated* pass.
                let loadAction: MTLLoadAction = cleared ? .load : .clear
                if let accumBroad {
                    accumulate(into: accumBroad, photo: photo, sample: sample, orientation: orientation,
                               gain: gain, feather: options.broadFeather, power: 1,
                               loadAction: loadAction, buffer: buffer)
                }
                if let accumDetail {
                    accumulate(into: accumDetail, photo: photo, sample: sample, orientation: orientation,
                               gain: gain, feather: options.feather, power: options.detailPower,
                               loadAction: loadAction, buffer: buffer)
                }
                cleared = true
                processed += 1
                buffer.commit()
                buffer.waitUntilCompleted()   // ensures `photo` can be freed now
                onProgress(0.20 + 0.65 * Double(processed) / Double(total), .projecting)
            }
        }

        guard cleared else { throw StitchError.noSamples }

        // Each accumulator is released as soon as it has been normalised, so the
        // two bands and the result are never all resident at full size at once.
        let broad = try normalized(&accumBroad)
        guard let bandBlender, accumDetail != nil else {
            poleFiller?.fill(broad)
            return broad
        }
        onProgress(0.86, .blending)
        let detail = try normalized(&accumDetail)
        let result = try makeTexture(width: width, height: height,
                                     usage: [.shaderRead, .renderTarget, .pixelFormatView])
        bandBlender.combine(broad: broad, detail: detail, into: result)
        poleFiller?.fill(result)   // dilate colour into alpha==0 gaps (no-op if disabled)
        return result
    }

    private func accumulate(into accumulator: MTLTexture,
                            photo: MTLTexture,
                            sample: CaptureSample,
                            orientation: simd_quatf,
                            gain: SIMD3<Float>,
                            feather: Float,
                            power: Float,
                            loadAction: MTLLoadAction,
                            buffer: MTLCommandBuffer) {
        guard let encoder = buffer.makeRenderCommandEncoder(
            descriptor: renderDescriptor(texture: accumulator, loadAction: loadAction)) else { return }

        var uniforms = ProjectorUniforms()
        uniforms.quaternion = orientation.vector
        uniforms.intrinsics = SIMD4<Float>(sample.intrinsics.fx, sample.intrinsics.fy,
                                           sample.intrinsics.cx, sample.intrinsics.cy)
        uniforms.imageSize = SIMD2<Float>(Float(sample.width), Float(sample.height))
        uniforms.outputSize = SIMD2<Float>(Float(options.outputWidth), Float(options.outputHeight))
        uniforms.gain = SIMD4<Float>(gain.x, gain.y, gain.z, power)
        uniforms.feather = feather

        encoder.setRenderPipelineState(accumulatePipeline)
        encoder.setFragmentTexture(photo, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ProjectorUniforms>.size, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
    }

    /// Divides an accumulator by its weight into a fresh texture and drops the
    /// caller's reference. Taking the source as a local means it dies when this
    /// function returns, which is what actually frees the memory.
    private func normalized(_ accumulator: inout MTLTexture?) throws -> MTLTexture {
        guard let source = accumulator else { throw StitchError.renderFailed }
        accumulator = nil
        let output = try makeTexture(width: options.outputWidth, height: options.outputHeight,
                                     usage: [.shaderRead, .renderTarget, .pixelFormatView])
        guard let buffer = commandQueue.makeCommandBuffer() else { throw StitchError.renderFailed }
        divide(accumulator: source, into: output, buffer: buffer)
        buffer.commit()
        buffer.waitUntilCompleted()
        return output
    }

    private func divide(accumulator: MTLTexture, into final: MTLTexture, buffer: MTLCommandBuffer) {
        guard let encoder = buffer.makeRenderCommandEncoder(
            descriptor: renderDescriptor(texture: final, loadAction: .dontCare)) else { return }
        encoder.setRenderPipelineState(dividePipeline)
        encoder.setFragmentTexture(accumulator, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
    }

    // MARK: - Helpers

    private func renderDescriptor(texture: MTLTexture, loadAction: MTLLoadAction) -> MTLRenderPassDescriptor {
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = texture
        desc.colorAttachments[0].loadAction = loadAction
        desc.colorAttachments[0].storeAction = .store
        desc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        return desc
    }

    private func makeTexture(width: Int, height: Int, usage: MTLTextureUsage) throws -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
        desc.usage = usage
        desc.storageMode = .private
        guard let texture = device.makeTexture(descriptor: desc) else { throw StitchError.renderFailed }
        return texture
    }

    /// Loads one photo, undistorting it first when the intrinsics carry a real
    /// lens profile (and the kill-switch is off). Identity intrinsics skip the
    /// pass — same raw-texture load as before, zero overhead. Output is topLeft.
    private func makePhotoTexture(cg: CGImage, sample: CaptureSample) throws -> MTLTexture {
        let intr = sample.intrinsics
        if !Self.undistortDisabled, let undistorter,
           intr.k1 != 0 || intr.k2 != 0 || intr.k3 != 0 {
            return try undistorter.undistort(cgImage: cg, intrinsics: intr)
        }
        let origin: MTKTextureLoader.Origin = options.textureOriginTopLeft ? .topLeft : .bottomLeft
        // Force an sRGB format so sampling always returns **linear** light.
        // Left to infer, the format depended on the file's colour profile, and
        // averaging gamma-encoded values is wrong anyway: two photos of the same
        // wall at different exposures do not average to the right brightness.
        return try textureLoader.newTexture(
            cgImage: cg,
            options: [.origin: origin,
                      .SRGB: NSNumber(value: true),
                      .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue)])
    }

    /// `PANORAMA_DISABLE_UNDISTORT=1` disables the pass everywhere (emergency revert).
    private static let undistortDisabled: Bool = {
        ProcessInfo.processInfo.environment["PANORAMA_DISABLE_UNDISTORT"] != nil
    }()

    /// `PANORAMA_DISABLE_GAINSOLVE=1` reverts to session-mean luminance gains.
    private static let gainSolveDisabled: Bool = {
        ProcessInfo.processInfo.environment["PANORAMA_DISABLE_GAINSOLVE"] != nil
    }()

    /// `PANORAMA_DISABLE_TWOBAND=1` reverts to a single weighted average.
    private static let twoBandDisabled: Bool = {
        ProcessInfo.processInfo.environment["PANORAMA_DISABLE_TWOBAND"] != nil
    }()

    private static func makePipeline(device: MTLDevice,
                                     vertex: MTLFunction,
                                     fragment: MTLFunction,
                                     format: MTLPixelFormat,
                                     blending: Bool) throws -> MTLRenderPipelineState {
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertex
        desc.fragmentFunction = fragment
        desc.colorAttachments[0].pixelFormat = format
        if blending {
            let att = desc.colorAttachments[0]
            att?.isBlendingEnabled = true
            att?.rgbBlendOperation = .add
            att?.alphaBlendOperation = .add
            att?.sourceRGBBlendFactor = .one
            att?.destinationRGBBlendFactor = .one
            att?.sourceAlphaBlendFactor = .one
            att?.destinationAlphaBlendFactor = .one
        }
        return try device.makeRenderPipelineState(descriptor: desc)
    }

    private static func makeSampler(device: MTLDevice) -> MTLSamplerState? {
        let desc = MTLSamplerDescriptor()
        desc.minFilter = .linear
        desc.magFilter = .linear
        desc.sAddressMode = .clampToEdge
        desc.tAddressMode = .clampToEdge
        return device.makeSamplerState(descriptor: desc)
    }

    static func loadCGImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func loadCIImage(_ url: URL) -> CIImage? {
        CIImage(contentsOf: url)
    }
}

// MARK: - Errors

public enum StitchError: LocalizedError {
    case metalUnavailable
    case noSamples
    case renderFailed

    public var errorDescription: String? {
        switch self {
        case .metalUnavailable: return "O Metal não está disponível neste dispositivo."
        case .noSamples: return "Nenhuma foto foi capturada para montar."
        case .renderFailed: return "A montagem falhou durante o processamento na GPU."
        }
    }
}
