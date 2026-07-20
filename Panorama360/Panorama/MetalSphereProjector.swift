import Foundation
import Metal
import MetalKit
import CoreImage

/// Primary stitcher. Warps each photo onto an equirectangular canvas by its
/// known ARKit/CoreMotion orientation and accumulates a weighted (exposure‑
/// matched) blend, then writes the result to disk.
///
/// Because every shot's orientation is known, this is a **direct projection** —
/// no feature matching, no homography search — which is far more robust than a
/// blind stitcher.
public final class MetalSphereProjector: PanoramaStitcher {

    public struct Options: Sendable {
        public var outputWidth: Int
        public var outputHeight: Int
        public var feather: Float            // 0..1 cross-fade strength at photo edges
        public var textureOriginTopLeft: Bool // toggle if the result is vertically flipped
        public init(outputWidth: Int = 4096,
                    outputHeight: Int = 2048,
                    feather: Float = 1.0,
                    textureOriginTopLeft: Bool = true) {
            self.outputWidth = outputWidth
            self.outputHeight = outputHeight
            self.feather = feather
            self.textureOriginTopLeft = textureOriginTopLeft
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

        // Stage: loading.
        onProgress(0.02, .loading)

        // Stage: exposure matching (lightweight — uses lazy CIImages).
        onProgress(0.08, .exposure)
        let gains = ExposureCompensator.gains(for: samples,
                                              loader: { Self.loadCIImage($0) },
                                              context: ciContext)

        // Stage: project + blend on the GPU. Textures are streamed one at a time
        // (see `render`) so peak memory stays bounded.
        onProgress(0.15, .projecting)
        let finalTexture = try render(samples: samples, gains: gains) { fraction in
            onProgress(0.15 + 0.70 * fraction, .projecting)
        }

        // Stage: finalize + write.
        onProgress(0.90, .finalizing)
        let ciImage = CIImage(mtlTexture: finalTexture, options: nil)?
            .transformed(by: CGAffineTransform(scaleX: 1, y: -1))
            .transformed(by: CGAffineTransform(translationX: 0, y: CGFloat(options.outputHeight)))
        guard let ciImage else { throw StitchError.renderFailed }

        try ImageWriter.write(ciImage, to: outputURL, context: ciContext, compressionQuality: 0.9)
        onProgress(1.0, .finalizing)
        return outputURL
    }

    // MARK: - Rendering

    /// Streams photos one texture at a time inside an autoreleasepool (peak VRAM
    /// ≈ 1 photo + 2 accumulators; loading all up front would be jetsam-killed).
    /// The final equirect is hole-filled at the end.
    private func render(samples: [CaptureSample],
                        gains: [Float],
                        onProgress: @escaping @Sendable (Double) -> Void) throws -> MTLTexture {

        let width = options.outputWidth, height = options.outputHeight
        let accumulator = try makeTexture(width: width, height: height,
                                          usage: [.shaderWrite, .shaderRead, .renderTarget])
        let final = try makeTexture(width: width, height: height,
                                    usage: [.shaderWrite, .shaderRead, .renderTarget, .pixelFormatView])

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
                let gain = i < gains.count ? gains[i] : 1.0
                // Clear the accumulator on the first *successfully accumulated* pass.
                let loadAction: MTLLoadAction = cleared ? .load : .clear
                accumulate(into: accumulator, photo: photo, sample: sample,
                           gain: gain, loadAction: loadAction, buffer: buffer)
                cleared = true
                processed += 1
                buffer.commit()
                buffer.waitUntilCompleted()   // ensures `photo` can be freed now
                onProgress(Double(processed) / Double(total))
            }
        }

        guard cleared else { throw StitchError.noSamples }

        guard let buffer = commandQueue.makeCommandBuffer() else { throw StitchError.renderFailed }
        divide(accumulator: accumulator, into: final, buffer: buffer)
        buffer.commit()
        buffer.waitUntilCompleted()
        poleFiller?.fill(final)   // dilate colour into alpha==0 gaps (no-op if disabled)
        return final
    }

    private func accumulate(into accumulator: MTLTexture,
                            photo: MTLTexture,
                            sample: CaptureSample,
                            gain: Float,
                            loadAction: MTLLoadAction,
                            buffer: MTLCommandBuffer) {
        guard let encoder = buffer.makeRenderCommandEncoder(
            descriptor: renderDescriptor(texture: accumulator, loadAction: loadAction)) else { return }

        var uniforms = ProjectorUniforms()
        uniforms.quaternion = sample.quaternion.vector
        uniforms.intrinsics = SIMD4<Float>(sample.intrinsics.fx, sample.intrinsics.fy,
                                           sample.intrinsics.cx, sample.intrinsics.cy)
        uniforms.imageSize = SIMD2<Float>(Float(sample.width), Float(sample.height))
        uniforms.outputSize = SIMD2<Float>(Float(options.outputWidth), Float(options.outputHeight))
        uniforms.exposureGain = gain
        uniforms.feather = options.feather

        encoder.setRenderPipelineState(accumulatePipeline)
        encoder.setFragmentTexture(photo, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ProjectorUniforms>.size, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
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
        return try textureLoader.newTexture(
            cgImage: cg,
            options: [.origin: origin,
                      .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue)])
    }

    /// `PANORAMA_DISABLE_UNDISTORT=1` disables the pass everywhere (emergency revert).
    private static let undistortDisabled: Bool = {
        ProcessInfo.processInfo.environment["PANORAMA_DISABLE_UNDISTORT"] != nil
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
