import Foundation
import SwiftUI

/// Top-level navigation between the three screens.
@MainActor
public final class AppRouter: ObservableObject {

    public enum Route: Equatable {
        case capture
        case stitching(PanoramaSession)
        case viewer(URL)
    }

    @Published public private(set) var route: Route = .capture

    /// Bumped on `goCapture()` so a fresh `CaptureView`/ViewModel is created even
    /// when returning from cancel.
    @Published public private(set) var captureGeneration: Int = 0

    public func goCapture() {
        captureGeneration &+= 1
        route = .capture
    }

    public func goStitching(_ session: PanoramaSession) {
        route = .stitching(session)
    }

    public func goViewer(_ url: URL) {
        route = .viewer(url)
    }
}
