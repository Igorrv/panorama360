import Foundation
import SwiftUI

/// Top-level navigation between onboarding and the three capture screens.
@MainActor
public final class AppRouter: ObservableObject {

    public enum Route: Equatable {
        case onboarding
        case capture
        case stitching(PanoramaSession)
        case viewer(URL)

        public static func == (lhs: Route, rhs: Route) -> Bool {
            switch (lhs, rhs) {
            case (.onboarding, .onboarding): return true
            case (.capture, .capture): return true
            case (.stitching(let a), .stitching(let b)): return a.id == b.id
            case (.viewer(let a), .viewer(let b)): return a == b
            default: return false
            }
        }
    }

    @Published public private(set) var route: Route

    /// Bumped on `goCapture()` so a fresh `CaptureView`/ViewModel is created even
    /// when returning from cancel/viewer.
    @Published public private(set) var captureGeneration: Int = 0

    /// True while the first-room tutorial is in progress — the capture screen
    /// uses the tiny `.tutorial` sphere distribution when this is set.
    @Published public private(set) var tutorialActive: Bool

    private let defaults = UserDefaults.standard
    private let onboardingKey = "panorama360.hasCompletedOnboarding"
    private let tutorialKey = "panorama360.tutorialActive"

    public init() {
        let completed = defaults.bool(forKey: onboardingKey)
        // Fresh install → onboarding; returning user → straight to capture.
        route = completed ? .capture : .onboarding
        tutorialActive = defaults.bool(forKey: tutorialKey)
    }

    // MARK: - Onboarding transitions

    /// Begin the guided first room (small sphere). Sets the tutorial flag and
    /// enters capture.
    public func startTutorial() {
        tutorialActive = true
        defaults.set(true, forKey: tutorialKey)
        goCapture()
    }

    /// Skip onboarding straight to full capture.
    public func skipOnboarding() {
        completeOnboarding()
        goCapture()
    }

    /// Return to the onboarding screen (e.g. user cancelled the tutorial room).
    public func goOnboarding() {
        tutorialActive = false
        defaults.set(false, forKey: tutorialKey)
        route = .onboarding
    }

    /// Called after the first room's panorama has been viewed: marks onboarding
    /// done and clears the tutorial flag so future launches go to full capture.
    public func completeOnboarding() {
        defaults.set(true, forKey: onboardingKey)
        tutorialActive = false
        defaults.set(false, forKey: tutorialKey)
    }

    // MARK: - Capture routing

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
