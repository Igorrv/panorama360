import Foundation

/// Orchestrates stitching for a session. An `actor` so two stitches can never
/// run concurrently (GPU + disk heavy). Reports progress to the UI.
public actor PanoramaEngine {

    public enum EngineError: LocalizedError {
        case nothingToStitch
        case alreadyRunning
        public var errorDescription: String? {
            switch self {
            case .nothingToStitch: return "There are no captured photos to stitch."
            case .alreadyRunning: return "Stitching is already in progress."
            }
        }
    }

    private let stitcher: PanoramaStitcher
    private let store: SessionStore
    private var running = false

    public init(stitcher: PanoramaStitcher, store: SessionStore) {
        self.stitcher = stitcher
        self.store = store
    }

    /// Convenience builder using the default Metal projector, sized to whatever
    /// this device can stitch without running out of memory.
    public static func `default`(store: SessionStore,
                                 options: MetalSphereProjector.Options = .adaptive()) throws -> PanoramaEngine {
        let projector = try MetalSphereProjector(options: options)
        return PanoramaEngine(stitcher: projector, store: store)
    }

    /// Runs the pipeline and returns the equirectangular image URL.
    public func stitch(session: PanoramaSession,
                       onProgress: @escaping @Sendable (Double, StitchStage) -> Void) async throws -> URL {
        guard !session.samples.isEmpty else { throw EngineError.nothingToStitch }
        guard !running else { throw EngineError.alreadyRunning }
        running = true
        defer { running = false }

        let url = store.stitchOutputURL(for: session.id)
        Log.stitch.info("Stitching \(session.samples.count) photos → \(url.lastPathComponent, privacy: .public)")
        let result = try await stitcher.stitch(samples: session.samples,
                                               into: url,
                                               onProgress: onProgress)
        var completedSession = session
        completedSession.equirectangularURL = result
        do {
            try store.persist(completedSession)
        } catch {
            // The panorama itself is already durable and can still be opened.
            // Keep the successful stitch, but leave a diagnostic for recovery.
            Log.storage.warning("Could not persist stitched session: \(error.localizedDescription, privacy: .public)")
        }
        Log.stitch.info("Stitching complete → \(result.lastPathComponent, privacy: .public)")
        return result
    }
}
