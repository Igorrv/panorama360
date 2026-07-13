import Foundation

/// Optional OpenCV-backed stitcher.
///
/// This file always compiles. The real `cv::Stitcher` implementation activates
/// automatically once `opencv2.xcframework` is linked (via `#if canImport`).
/// Without the framework, calling `stitch` throws a clear instruction. See
/// `docs/OpenCVIntegration.md`.
///
/// **When to use it:** `cv::Stitcher` adds feature-based bundle adjustment and
/// multi-band seam blending on top of the orientation we already know. For most
/// v1 captures the pure-Apple `MetalSphereProjector` (which leverages the exact
/// per-shot orientation) is more reliable; OpenCV is the upgrade path.
public final class OpenCVStitcher: PanoramaStitcher {

    #if canImport(opencv2)
    public init() {}

    public func stitch(samples: [CaptureSample],
                       into outputURL: URL,
                       onProgress: @escaping @Sendable (Double, StitchStage) -> Void) async throws -> URL {
        // TODO(opencv): bridge to cv::Stitcher here once the xcframework is linked.
        // 1. Load each sample into cv::Mat (optionally undistort with its intrinsics).
        // 2. Create cv::Stitcher (SCANS mode benefits from the known order/orientation).
        // 3. stitch(...) → cv::Mat pano.
        // 4. Encode to HEIC/PNG at outputURL.
        // Report progress via onProgress between stages.
        throw OpenCVStitcher.notLinked
    }
    #else
    public init() {}

    public func stitch(samples: [CaptureSample],
                       into outputURL: URL,
                       onProgress: @escaping @Sendable (Double, StitchStage) -> Void) async throws -> URL {
        throw OpenCVStitcher.notLinked
    }
    #endif

    static var notLinked: Error {
        NSError(domain: "Panorama360", code: 101, userInfo: [
            NSLocalizedDescriptionKey: "OpenCV is not linked. Add opencv2.xcframework to the Panorama360 target and rebuild — see docs/OpenCVIntegration.md."
        ])
    }
}
