import Foundation
import Metal
import MetalKit
import CoreGraphics

/// Metal inverse-map lens undistortion. Renders a corrected `.bgra8Unorm` copy
/// of a captured photo using its Brown–Conrady coefficients, so the projection
/// stitcher sees rectilinear geometry and seams line up. The output is a
/// drop-in replacement for the raw photo texture (same orientation, topLeft).
///
/// The caller skips this entirely when the profile is identity (k1=k2=k3=0) —
/// zero overhead for uncharacterised lenses. Streaming-safe: each call loads
/// one source texture, renders, and `waitUntilCompleted`s before returning so
/// the source can be freed.
public final class Undistorter {

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let textureLoader: MTKTextureLoader

    public init(device: MTLDevice, commandQueue: MTLCommandQueue) throws {
        self.device = device
        self.commandQueue = commandQueue
        guard let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "undistort_vertex"),
              let fragment = library.makeFunction(name: "undistort_fragment") else {
            throw StitchError.metalUnavailable
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertex
        desc.fragmentFunction = fragment
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        do {
            pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            Log.stitch.error("Undistort pipeline error: \(error.localizedDescription, privacy: .public)")
            throw StitchError.renderFailed
        }
        sampler = try Self.makeSampler(device: device)
        textureLoader = MTKTextureLoader(device: device)
    }

    /// Loads `cgImage` and renders an undistorted copy at the same size. Use the
    /// result in place of the raw photo texture for accumulation.
    public func undistort(cgImage: CGImage, intrinsics: CameraIntrinsics) throws -> MTLTexture {
        let width = cgImage.width, height = cgImage.height
        let srcOpts: [MTKTextureLoader.Option: Any] = [
            .origin: MTKTextureLoader.Origin.topLeft,   // matches the projector's load convention
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue)
        ]
        let src = try textureLoader.newTexture(cgImage: cgImage, options: srcOpts)
        let dst = try Self.makeTexture(device: device, width: width, height: height,
                                       usage: [.shaderWrite, .shaderRead, .renderTarget])

        var uniforms = UndistortUniforms(fx: intrinsics.fx, fy: intrinsics.fy,
                                         cx: intrinsics.cx, cy: intrinsics.cy,
                                         k1: intrinsics.k1, k2: intrinsics.k2, k3: intrinsics.k3)
        guard let buffer = commandQueue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(
                descriptor: Self.passDescriptor(texture: dst)) else {
            throw StitchError.renderFailed
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(src, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<UndistortUniforms>.size, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encoder.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()   // retires the write; frees `src`
        return dst
    }

    // MARK: - Metal helpers

    /// Must match `UndistortUniforms` in UndistortShaders.metal byte-for-byte.
    private struct UndistortUniforms {
        var fx: Float; var fy: Float; var cx: Float; var cy: Float
        var k1: Float; var k2: Float; var k3: Float
        var pad: Float = 0
    }

    private static func passDescriptor(texture: MTLTexture) -> MTLRenderPassDescriptor {
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = texture
        desc.colorAttachments[0].loadAction = .dontCare
        desc.colorAttachments[0].storeAction = .store
        return desc
    }

    private static func makeTexture(device: MTLDevice, width: Int, height: Int,
                                    usage: MTLTextureUsage) throws -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        desc.usage = usage
        desc.storageMode = .private
        guard let texture = device.makeTexture(descriptor: desc) else { throw StitchError.renderFailed }
        return texture
    }

    private static func makeSampler(device: MTLDevice) throws -> MTLSamplerState {
        let desc = MTLSamplerDescriptor()
        desc.minFilter = .linear
        desc.magFilter = .linear
        desc.sAddressMode = .clampToEdge
        desc.tAddressMode = .clampToEdge
        guard let s = device.makeSamplerState(descriptor: desc) else { throw StitchError.renderFailed }
        return s
    }
}
