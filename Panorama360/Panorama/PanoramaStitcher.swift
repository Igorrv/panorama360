import Foundation

/// Coarse pipeline stages surfaced in the stitching UI.
public enum StitchStage: String, Sendable, CaseIterable {
    case loading      = "Loading images"
    case undistorting = "Correcting lens"
    case exposure     = "Matching exposure"
    case projecting   = "Projecting onto sphere"
    case finalizing   = "Finalizing"

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
