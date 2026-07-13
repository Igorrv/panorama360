import Foundation
import SwiftUI
import Metal

/// Owns the `ViewerEngine` and the panorama being displayed.
@MainActor
public final class ViewerViewModel: ObservableObject {

    public let engine = ViewerEngine()
    @Published public private(set) var isLoaded: Bool = false
    @Published public private(set) var errorMessage: String?

    public private(set) var panoramaURL: URL?

    public init() {}

    public func configure(url: URL) {
        panoramaURL = url
    }

    /// Called once by the hosting view after it has created the Metal renderer.
    public func attach(renderer: PanoramaRenderer) {
        if let panoramaURL {
            renderer.loadPanogram(at: panoramaURL)
        }
        engine.attach(renderer: renderer)
        isLoaded = true
    }

    public func toggleGyro() {
        engine.gyroEnabled ? engine.stopGyro() : engine.startGyro()
    }
}
