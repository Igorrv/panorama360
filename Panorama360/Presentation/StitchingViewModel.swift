import Foundation
import SwiftUI

/// Runs the stitching pipeline and reports progress + the final stage to the UI.
@MainActor
public final class StitchingViewModel: ObservableObject {

    @Published public private(set) var progress: Double = 0
    @Published public private(set) var stage: StitchStage = .loading
    @Published public private(set) var didFinish: Bool = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var outputURL: URL?

    private let store: SessionStore
    private var engine: PanoramaEngine?
    public var onComplete: ((URL) -> Void)?
    public var onFailed: (() -> Void)?

    public init(store: SessionStore = SessionStore()) {
        self.store = store
    }

    /// Clears the current error banner.
    public func dismissError() { errorMessage = nil }

    public func run(session: PanoramaSession) {
        Task {
            do {
                let engine = try PanoramaEngine.default(store: store)
                self.engine = engine
                let url = try await engine.stitch(session: session) { [weak self] fraction, stage in
                    Task { @MainActor in
                        self?.progress = fraction
                        self?.stage = stage
                    }
                }
                self.outputURL = url
                self.didFinish = true
                Haptics.shared.finished()
                self.onComplete?(url)
            } catch {
                self.errorMessage = error.localizedDescription
                self.onFailed?()
            }
        }
    }
}
