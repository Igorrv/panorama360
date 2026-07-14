import Foundation
import Metal
import MetalKit

/// Builds the live, growing 360° globe one capture at a time.
///
/// Each call to `add(_:)` streams **one** photo: it loads that photo as a Metal
/// texture, warps it onto the equirectangular accumulator by the photo's known
/// orientation (`accumulate_fragment`), runs the divide pass into `previewTexture`
/// (`divide_fragment`), then frees the photo. The globe therefore fills in
/// progressively and never disappears.
///
/// ### Threading / crash-safety invariants (do not break)
/// - This is an **actor**, not `@MainActor`: `MTKTextureLoader.newTexture` and
///   `buffer.waitUntilCompleted()` block for tens of milliseconds and must not
///   stall the UI. The view-model calls `await reconstruction.add(sample)`,
///   suspending the main actor so SwiftUI / the globe renderer keep running.
/// - `previewTexture` is a `nonisolated let` allocated **once** in `create`.
///   Its *reference* is immutable; only its texels are overwritten per `add`.
///   The globe renderer reads this reference off-actor with no lock.
/// - `device` and `commandQueue` are **shared** with `SpatialFragmentRenderer`.
///   Metal serializes command buffers only within one queue, so a shared queue
///   is what makes the renderer's reads of `previewTexture` safe against this
///   manager's writes — no fence or event needed. Splitting the queues would be
///   a torn-read hazard.
public actor LiveReconstructionManager {

    /// The divided equirectangular preview the globe samples each frame.
    /// Black where uncovered, filled where a capture has landed.
    public nonisolated let previewTexture: MTLTexture?

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let accumulatePipeline: MTLRenderPipelineState
    private let dividePipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let textureLoader: MTKTextureLoader
    private let accumulator: MTLTexture
    private let outputSize: SIMD2<Int>
    /// False until the first successful accumulate pass; the first pass clears
    /// the accumulator, later passes load+add.
    private var cleared = false

    /// Live preview resolution. Smaller than the stitcher's 4096×2048 so the
    /// per-capture passes are fast; the authoritative stitch re-runs at full size.
    private static let previewWidth = 2048
    private static let previewHeight = 1024

    private init(device: MTLDevice,
                 commandQueue: MTLCommandQueue,
                 accumulatePipeline: MTLRenderPipelineState,
                 dividePipeline: MTLRenderPipelineState,
                 sampler: MTLSamplerState,
                 textureLoader: MTKTextureLoader,
                 accumulator: MTLTexture,
                 previewTexture: MTLTexture,
                 outputSize: SIMD2<Int>) {
        self.device = device
        self.commandQueue = commandQueue
        self.accumulatePipeline = accumulatePipeline
        self.dividePipeline = dividePipeline
        self.sampler = sampler
        self.textureLoader = textureLoader
        self.accumulator = accumulator
        self.previewTexture = previewTexture
        self.outputSize = outputSize
    }

    /// Builds the manager against an existing device+queue (shared with the
    /// renderer). Returns `nil` if Metal setup fails — the caller then runs the
    /// capture screen without a live globe (degraded but safe).
    public static func create(device: MTLDevice,
                              commandQueue: MTLCommandQueue) -> LiveReconstructionManager? {
        guard let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "quad_vertex"),
              let accumulateFn = library.makeFunction(name: "accumulate_fragment"),
              let divideFn = library.makeFunction(name: "divide_fragment") else {
            Log.recon.error("Missing shader functions for live reconstruction.")
            return nil
        }

        let accumulatePipeline: MTLRenderPipelineState
        let dividePipeline: MTLRenderPipelineState
        do {
            accumulatePipeline = try makePipeline(device: device,
                                                  vertex: vertex, fragment: accumulateFn,
                                                  blending: true)
            dividePipeline = try makePipeline(device: device,
                                              vertex: vertex, fragment: divideFn,
                                              blending: false)
        } catch {
            Log.recon.error("Live-recon pipeline error: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        let size = SIMD2<Int>(previewWidth, previewHeight)
        guard let accumulator = makeTexture(device: device, width: previewWidth, height: previewHeight,
                                            usage: [.shaderWrite, .shaderRead, .renderTarget]),
              let preview = makeTexture(device: device, width: previewWidth, height: previewHeight,
                                        usage: [.shaderWrite, .shaderRead, .renderTarget]) else {
            Log.recon.error("Could not allocate live-recon accumulator textures.")
            return nil
        }

        return LiveReconstructionManager(
            device: device,
            commandQueue: commandQueue,
            accumulatePipeline: accumulatePipeline,
            dividePipeline: dividePipeline,
            sampler: makeSampler(device: device),
            textureLoader: MTKTextureLoader(device: device),
            accumulator: accumulator,
            previewTexture: preview,
            outputSize: size)
    }

    // MARK: - Incremental accumulate

    /// Adds one captured photo to the live globe. Safe to call from the main
    /// actor via `await`; the blocking work runs on this actor's executor.
    public func add(_ sample: CaptureSample) async {
        guard let preview = previewTexture else { return }
        do {
            try autoreleasepool {
                guard let cg = MetalSphereProjector.loadCGImage(sample.imageURL) else {
                    Log.recon.warning("Skipping unreadable live image \(sample.imageURL.lastPathComponent, privacy: .public)")
                    return
                }
                let photo = try textureLoader.newTexture(
                    cgImage: cg,
                    options: [.origin: MTKTextureLoader.Origin.topLeft,
                              .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue)])

                guard let buffer = commandQueue.makeCommandBuffer() else { return }
                let loadAction: MTLLoadAction = cleared ? .load : .clear
                accumulate(into: accumulator, photo: photo, sample: sample,
                           loadAction: loadAction, buffer: buffer)
                cleared = true
                buffer.commit()
                buffer.waitUntilCompleted()   // retires the write; frees `photo`

                // Divide the accumulated (color·w, w) into the preview the globe samples.
                guard let divBuffer = commandQueue.makeCommandBuffer() else { return }
                divide(accumulator: accumulator, into: preview, buffer: divBuffer)
                divBuffer.commit()
                divBuffer.waitUntilCompleted()
            }
        } catch {
            Log.recon.error("Live accumulate failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Clears the accumulator so a reused manager starts blank (e.g. a fresh
    /// capture). Safe no-op if never allocated.
    public func reset() async {
        guard cleared else { return }
        cleared = false
        // Next add() will .clear the accumulator; no extra command buffer needed.
    }

    // MARK: - Render passes (mirror MetalSphereProjector, trimmed)

    private func accumulate(into accumulator: MTLTexture,
                            photo: MTLTexture,
                            sample: CaptureSample,
                            loadAction: MTLLoadAction,
                            buffer: MTLCommandBuffer) {
        guard let encoder = buffer.makeRenderCommandEncoder(
            descriptor: Self.passDescriptor(texture: accumulator, loadAction: loadAction)) else { return }

        var uniforms = ProjectorUniforms()
        uniforms.quaternion = sample.quaternion.vector
        uniforms.intrinsics = SIMD4<Float>(sample.intrinsics.fx, sample.intrinsics.fy,
                                           sample.intrinsics.cx, sample.intrinsics.cy)
        uniforms.imageSize = SIMD2<Float>(Float(sample.width), Float(sample.height))
        uniforms.outputSize = SIMD2<Float>(Float(outputSize.x), Float(outputSize.y))
        uniforms.exposureGain = 1.0
        uniforms.feather = 1.0

        encoder.setRenderPipelineState(accumulatePipeline)
        encoder.setFragmentTexture(photo, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ProjectorUniforms>.size, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
    }

    private func divide(accumulator: MTLTexture, into final: MTLTexture, buffer: MTLCommandBuffer) {
        guard let encoder = buffer.makeRenderCommandEncoder(
            descriptor: Self.passDescriptor(texture: final, loadAction: .dontCare)) else { return }
        encoder.setRenderPipelineState(dividePipeline)
        encoder.setFragmentTexture(accumulator, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
    }

    // MARK: - Metal helpers (static so `create` can use them pre-init)

    private static func passDescriptor(texture: MTLTexture, loadAction: MTLLoadAction) -> MTLRenderPassDescriptor {
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = texture
        desc.colorAttachments[0].loadAction = loadAction
        desc.colorAttachments[0].storeAction = .store
        desc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        return desc
    }

    private static func makeTexture(device: MTLDevice, width: Int, height: Int,
                                    usage: MTLTextureUsage) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
        desc.usage = usage
        desc.storageMode = .private
        return device.makeTexture(descriptor: desc)
    }

    private static func makePipeline(device: MTLDevice,
                                     vertex: MTLFunction,
                                     fragment: MTLFunction,
                                     blending: Bool) throws -> MTLRenderPipelineState {
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertex
        desc.fragmentFunction = fragment
        desc.colorAttachments[0].pixelFormat = .rgba16Float
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

    private static func makeSampler(device: MTLDevice) -> MTLSamplerState {
        let desc = MTLSamplerDescriptor()
        desc.minFilter = .linear
        desc.magFilter = .linear
        desc.sAddressMode = .clampToEdge
        desc.tAddressMode = .clampToEdge
        return device.makeSamplerState(descriptor: desc)!
    }
}
