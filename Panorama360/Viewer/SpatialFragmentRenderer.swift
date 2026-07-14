import Foundation
import Metal
import MetalKit
import simd

/// `MTKViewDelegate` that draws the **live** 360° globe (the progressive
/// reconstruction) on the inside of a sphere. A near-clone of `PanoramaRenderer`
/// with two differences:
///
/// 1. It samples `LiveReconstructionManager.previewTexture` (the growing
///    equirect) instead of a single finished panorama — re-binding it every
///    frame so newly accumulated regions appear immediately.
/// 2. Its view matrix is driven by the **live device orientation** (via
///    `updateOrientation`) so the globe turns as the user turns the phone —
///    filled regions rotate into view, reinforcing "I'm filling the space
///    around me".
///
/// Shares the manager's `MTLDevice` + `MTLCommandQueue`; see the concurrency
/// invariant on `LiveReconstructionManager`.
public final class SpatialFragmentRenderer: NSObject, MTKViewDelegate {

    public var uniforms = ViewerUniforms()

    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let positionsBuffer: MTLBuffer
    private let vertexCount: Int
    private let previewTexture: MTLTexture?

    public init?(device: MTLDevice,
                 commandQueue: MTLCommandQueue,
                 previewTexture: MTLTexture?) {
        self.commandQueue = commandQueue
        self.previewTexture = previewTexture

        guard let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "viewer_vertex"),
              let fragment = library.makeFunction(name: "viewer_fragment") else {
            Log.recon.error("Missing viewer shader functions.")
            return nil
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertex
        desc.fragmentFunction = fragment
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        let pipeline: MTLRenderPipelineState
        do {
            pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            Log.recon.error("Globe pipeline error: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        self.pipeline = pipeline

        let positions = SphereMesh.positions()
        vertexCount = positions.count
        guard let buffer = device.makeBuffer(bytes: positions,
                                             length: positions.count * MemoryLayout<SIMD3<Float>>.size,
                                             options: []) else { return nil }
        positionsBuffer = buffer

        let sdesc = MTLSamplerDescriptor()
        sdesc.minFilter = .linear
        sdesc.magFilter = .linear
        sdesc.sAddressMode = .clampToEdge
        sdesc.tAddressMode = .clampToEdge
        sampler = device.makeSamplerState(descriptor: sdesc)!

        super.init()
        uniforms.fovRadians = 1.2          // ~69° — wide enough to read the PiP globe
        uniforms.aspect = 1.0
    }

    // MARK: - Orientation

    /// Drives the globe from the live device orientation, via the shared
    /// pose-projection seam. At session start the relative orientation is
    /// identity, so the first capture sits dead-centre, and turning right brings
    /// the next region into view.
    public func updateOrientation(_ orientation: DeviceOrientation) {
        let angles = PoseProjectionEngine.liveViewAngles(orientation: orientation)
        let yawQ = simd_quatf(angle: angles.yaw, axis: SIMD3<Float>(0, 1, 0))
        let pitchQ = simd_quatf(angle: angles.pitch, axis: SIMD3<Float>(1, 0, 0))
        uniforms.viewMatrix = simd_float4x4(yawQ) * simd_float4x4(pitchQ)
    }

    // MARK: - MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        uniforms.aspect = Float(size.width / max(size.height, 1))
    }

    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let passDescriptor = view.currentRenderPassDescriptor,
              let previewTexture else { return }

        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let buffer = commandQueue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }

        encoder.setRenderPipelineState(pipeline)
        encoder.setCullMode(.none)   // render both faces so the inside is visible
        encoder.setVertexBuffer(positionsBuffer, offset: 0, index: 0)
        var u = uniforms
        encoder.setVertexBytes(&u, length: MemoryLayout<ViewerUniforms>.size, index: 1)
        encoder.setFragmentTexture(previewTexture, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
        encoder.endEncoding()

        buffer.present(drawable)
        buffer.commit()
    }
}
