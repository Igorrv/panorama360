import Foundation
import Metal

/// Combines the two accumulation bands into the final equirect.
///
/// A single weighted average has to pick one feather width and loses either way:
/// a wide one smears detail and doubles every misaligned edge into a ghost, a
/// narrow one leaves visible exposure steps at the seams. Two bands split the
/// difference — low frequencies come from the wide cross-fade, high frequencies
/// from the sharp one:
///
///     result = blur(broad) + (detail − blur(detail))
///
/// The blur runs on a 1/8-scale copy (low frequencies do not need full
/// resolution), so the extra cost is a few hundred KB and a handful of passes.
public final class BandBlender {

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let downsamplePipeline: MTLRenderPipelineState
    private let blurPipeline: MTLRenderPipelineState
    private let combinePipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState

    private let lowBroad: MTLTexture
    private let lowDetail: MTLTexture
    private let scratch: MTLTexture
    private let lowWidth: Int
    private let lowHeight: Int

    public init(device: MTLDevice, commandQueue: MTLCommandQueue,
                width: Int, height: Int) throws {
        self.device = device
        self.commandQueue = commandQueue

        guard let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "band_vertex"),
              let downsample = library.makeFunction(name: "band_downsample"),
              let blur = library.makeFunction(name: "band_blur"),
              let combine = library.makeFunction(name: "band_combine") else {
            throw StitchError.metalUnavailable
        }
        downsamplePipeline = try Self.makePipeline(device: device, vertex: vertex, fragment: downsample)
        blurPipeline = try Self.makePipeline(device: device, vertex: vertex, fragment: blur)
        combinePipeline = try Self.makePipeline(device: device, vertex: vertex, fragment: combine)

        // Repeat in longitude (the equirect wraps at ±180°), clamp in latitude.
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .repeat
        samplerDesc.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDesc) else {
            throw StitchError.renderFailed
        }
        self.sampler = sampler

        lowWidth = max(width / 8, 32)
        lowHeight = max(height / 8, 16)
        lowBroad = try Self.makeTexture(device: device, width: lowWidth, height: lowHeight)
        lowDetail = try Self.makeTexture(device: device, width: lowWidth, height: lowHeight)
        scratch = try Self.makeTexture(device: device, width: lowWidth, height: lowHeight)
    }

    /// Writes `blur(broad) + (detail − blur(detail))` into `output`.
    /// `broad` and `detail` must both be normalised equirects of the same size.
    public func combine(broad: MTLTexture, detail: MTLTexture, into output: MTLTexture) {
        guard let buffer = commandQueue.makeCommandBuffer() else { return }
        lowBand(of: broad, into: lowBroad, buffer: buffer)
        lowBand(of: detail, into: lowDetail, buffer: buffer)

        guard let encoder = buffer.makeRenderCommandEncoder(
            descriptor: Self.passDescriptor(texture: output)) else { return }
        encoder.setRenderPipelineState(combinePipeline)
        encoder.setFragmentTexture(detail, index: 0)
        encoder.setFragmentTexture(lowBroad, index: 1)
        encoder.setFragmentTexture(lowDetail, index: 2)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()

        buffer.commit()
        buffer.waitUntilCompleted()
    }

    // MARK: - Passes

    /// Downsample → horizontal blur → vertical blur (normalising on the way out).
    private func lowBand(of source: MTLTexture, into destination: MTLTexture,
                         buffer: MTLCommandBuffer) {
        draw(pipeline: downsamplePipeline, source: source, destination: destination,
             uniforms: BandUniforms(stepX: 1 / Float(lowWidth), stepY: 1 / Float(lowHeight),
                                    normalizeOut: 0),
             buffer: buffer)
        draw(pipeline: blurPipeline, source: destination, destination: scratch,
             uniforms: BandUniforms(stepX: 1 / Float(lowWidth), stepY: 0, normalizeOut: 0),
             buffer: buffer)
        draw(pipeline: blurPipeline, source: scratch, destination: destination,
             uniforms: BandUniforms(stepX: 0, stepY: 1 / Float(lowHeight), normalizeOut: 1),
             buffer: buffer)
    }

    private func draw(pipeline: MTLRenderPipelineState,
                      source: MTLTexture,
                      destination: MTLTexture,
                      uniforms: BandUniforms,
                      buffer: MTLCommandBuffer) {
        guard let encoder = buffer.makeRenderCommandEncoder(
            descriptor: Self.passDescriptor(texture: destination)) else { return }
        var uniforms = uniforms
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<BandUniforms>.size, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
    }

    // MARK: - Metal helpers

    /// Must match `BandUniforms` in BlendShaders.metal byte-for-byte.
    private struct BandUniforms {
        var stepX: Float
        var stepY: Float
        var normalizeOut: Float
        var pad0: Float = 0
    }

    private static func makePipeline(device: MTLDevice,
                                     vertex: MTLFunction,
                                     fragment: MTLFunction) throws -> MTLRenderPipelineState {
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertex
        desc.fragmentFunction = fragment
        desc.colorAttachments[0].pixelFormat = .rgba16Float
        do {
            return try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            Log.stitch.error("BandBlender pipeline error: \(error.localizedDescription, privacy: .public)")
            throw StitchError.renderFailed
        }
    }

    private static func passDescriptor(texture: MTLTexture) -> MTLRenderPassDescriptor {
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = texture
        desc.colorAttachments[0].loadAction = .dontCare
        desc.colorAttachments[0].storeAction = .store
        return desc
    }

    private static func makeTexture(device: MTLDevice, width: Int, height: Int) throws -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
        desc.usage = [.shaderRead, .renderTarget]
        desc.storageMode = .private
        guard let texture = device.makeTexture(descriptor: desc) else { throw StitchError.renderFailed }
        return texture
    }
}
