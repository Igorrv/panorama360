import Foundation
import simd

/// Swift-side uniforms for the Metal viewer + projector.
///
/// **Keep in sync with `Viewer/ShaderTypes.h`** — the two are passed
/// byte-for-byte between Swift and Metal, so the field order and types must
/// match exactly. Duplicated (rather than bridged) so the structs get clean
/// default initializers and there is no Objective-C bridging header to maintain.
public struct ViewerUniforms {
    public var viewMatrix: simd_float4x4 = matrix_identity_float4x4
    public var fovRadians: Float = 1.2
    public var aspect: Float = 1.0
    public var pad: SIMD2<Float> = .zero
    public init() {}
}

public struct ProjectorUniforms {
    public var quaternion: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 1)   // (x, y, z, w)
    public var intrinsics: SIMD4<Float> = SIMD4<Float>(1, 1, 0, 0)   // fx, fy, cx, cy
    public var imageSize: SIMD2<Float> = .zero
    public var outputSize: SIMD2<Float> = .zero
    public var exposureGain: Float = 1.0
    public var feather: Float = 1.0
    public var pad: SIMD2<Float> = .zero
    public init() {}
}
