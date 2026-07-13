import Foundation
import Metal
import MetalKit

/// `MTKViewDelegate` that draws the equirectangular panorama on the inside of
/// a sphere. Reads `uniforms` (updated by `ViewerEngine`) on every frame.
public final class PanoramaRenderer: NSObject, MTKViewDelegate {

    public var uniforms = ViewerUniforms()

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let positionsBuffer: MTLBuffer
    private let vertexCount: Int
    private let textureLoader: MTKTextureLoader
    private var panoTexture: MTLTexture?

    public init?(device: MTLDevice) {
        self.device = device
        guard let commandQueue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else {
            Log.viewer.error("Metal init failed.")
            return nil
        }
        self.commandQueue = commandQueue
        self.textureLoader = MTKTextureLoader(device: device)

        guard let vertex = library.makeFunction(name: "viewer_vertex"),
              let fragment = library.makeFunction(name: "viewer_fragment") else { return nil }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertex
        desc.fragmentFunction = fragment
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        do {
            pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            Log.viewer.error("Pipeline error: \(error.localizedDescription, privacy: .public)")
            return nil
        }

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
        uniforms.fovRadians = 1.2
        uniforms.aspect = 1.0
    }

    // MARK: - Texture

    public func loadPanogram(at url: URL) {
        guard let cgImage = MetalSphereProjector.loadCGImage(url) else {
            Log.viewer.error("Could not load panorama image.")
            return
        }
        let opts: [MTKTextureLoader.Option: Any] = [
            .origin: MTKTextureLoader.Origin.bottomLeft,
            .usage: MTLTextureUsage.shaderRead.rawValue
        ]
        do {
            panoTexture = try textureLoader.newTexture(cgImage: cgImage, options: opts)
            Log.viewer.info("Loaded panorama \(url.lastPathComponent, privacy: .public)")
        } catch {
            Log.viewer.error("Texture load error: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        uniforms.aspect = Float(size.width / max(size.height, 1))
    }

    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let passDescriptor = view.currentRenderPassDescriptor,
              let panoTexture else { return }

        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let buffer = commandQueue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }

        encoder.setRenderPipelineState(pipeline)
        encoder.setCullMode(.none) // render both faces so the inside is always visible
        encoder.setVertexBuffer(positionsBuffer, offset: 0, index: 0)
        var u = uniforms
        encoder.setVertexBytes(&u, length: MemoryLayout<ViewerUniforms>.size, index: 1)
        encoder.setFragmentTexture(panoTexture, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
        encoder.endEncoding()

        buffer.present(drawable)
        buffer.commit()
    }
}
