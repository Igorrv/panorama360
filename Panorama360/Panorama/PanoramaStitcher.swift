import Foundation

/// Coarse pipeline stages surfaced in the stitching UI.
public enum StitchStage: String, Sendable, CaseIterable {
    case loading      = "Carregando imagens"
    case undistorting = "Corrigindo lente"
    case exposure     = "Equalizando exposição"
    case projecting   = "Projetando na esfera"
    case blending     = "Fundindo as costuras"
    case finalizing   = "Finalizando"

    public var order: Int {
        StitchStage.allCases.firstIndex(of: self) ?? 0
    }
}

/// Implementations stitch a set of oriented photos into a single equirectangular
/// image written to `outputURL`.
public protocol PanoramaStitcher: Sendable {
    func stitch(samples: [CaptureSample],
                into outputURL: URL,
                onProgress: @escaping @Sendable (Double, StitchStage) -> Void) async throws -> URL
}
