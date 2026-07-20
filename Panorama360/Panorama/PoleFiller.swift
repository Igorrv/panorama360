import Foundation
import Metal

/// Fills uncovered gaps (poles, thin seams) in the final equirectangular texture
/// by morphological dilation: each pass copies the nearest covered texel into
/// alpha==0 neighbours, shrinking every hole boundary by `step` pixels. After
/// `divide_fragment` marks uncovered texels with alpha 0, this eliminates the
/// black holes that break immersion for real-estate viewing.
///
/// Runs only on the authoritative stitch (`MetalSphereProjector.render`), not the
/// live preview globe. `iterations` defaults to 6 with a doubling step (reach
/// ~63px). Env `PANORAMA_POLEFILL_ITERS=0` disables it (kill-switch).
public final class PoleFiller {

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let scratchA: MTLTexture
    private let scratchB: MTLTexture

    public init(device: MTLDevice, commandQueue: MTLCommandQueue,
                width: Int, height: Int) throws {
        self.device = device
        self.commandQueue = commandQueue
        guard let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "polefill_vertex"),
              let fragment = library.makeFunction(name: "dilate_fragment") else {
            throw StitchError.metalUnavailable
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertex
        desc.fragmentFunction = fragment
        desc.colorAttachments[0].pixelFormat = .rgba16Float
        do {
            pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            Log.stitch.error("PoleFill pipeline error: \(error.localizedDescription, privacy: .public)")
            throw StitchError.renderFailed
        }
        scratchA = try Self.makeTexture(device: device, width: width, height: height)
        scratchB = try Self.makeTexture(device: device, width: width, height: height)
    }

    /// Fills alpha==0 gaps in `target` **in place**. No-op when disabled or when
    /// the texture size does not match the scratch buffers.
    public func fill(_ target: MTLTexture) {
        let iterations = Self.iterations
        guard iterations > 0,
              target.width == scratchA.width, target.height == scratchA.height else { return }

        guard let buffer = commandQueue.makeCommandBuffer() else { return }
        var source: MTLTexture = target
        var dest: MTLTexture = scratchA
        for i in 0..<iterations {
            // Doubling step: pass i reaches 2^i px beyond the covered boundary
            // (cumulative ~63px over 6 passes), capped to avoid giant colour bleeds.
            let step = min(1 << i, 64)
            dilate(src: source, into: dest, step: step, buffer: buffer)
            source = dest
            dest = (dest === scratchA) ? scratchB : scratchA
        }
        blit(from: source, to: target, buffer: buffer)
        buffer.commit()
        buffer.waitUntilCompleted()
    }

    // MARK: - Passes

    private func dilate(src: MTLTexture, into dest: MTLTexture,
                        step: Int, buffer: MTLCommandBuffer) {
        guard let encoder = buffer.makeRenderCommandEncoder(
            descriptor: Self.passDescriptor(texture: dest)) else { return }
        var uniforms = PoleFillUniforms(stepPixels: Float(step))
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(src, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<PoleFillUniforms>.size, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
    }

    private func blit(from src: MTLTexture, to dest: MTLTexture, buffer: MTLCommandBuffer) {
        guard let encoder = buffer.makeBlitCommandEncoder() else { return }
        encoder.copy(from: src, sourceSlice: 0, sourceLevel: 0,
                     sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                     sourceSize: MTLSize(width: src.width, height: src.height, depth: 1),
                     to: dest, destinationSlice: 0, destinationLevel: 0,
                     destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        encoder.endEncoding()
    }

    // MARK: - Metal helpers

    /// Must match `PoleFillUniforms` in PoleFillShaders.metal byte-for-byte.
    private struct PoleFillUniforms {
        var stepPixels: Float
        var pad0: Float = 0
        var pad1: Float = 0
        var pad2: Float = 0
    }

    /// Default 6 passes (doubling → ~63px reach). Env override clamped 0…12; 0 disables.
    private static let iterations: Int = {
        if let v = ProcessInfo.processInfo.environment["PANORAMA_POLEFILL_ITERS"],
           let n = Int(v) { return max(0, min(n, 12)) }
        return 6
    }()

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
        desc.usage = [.shaderWrite, .shaderRead, .renderTarget]
        desc.storageMode = .private
        guard let t = device.makeTexture(descriptor: desc) else { throw StitchError.renderFailed }
        return t
    }
}
