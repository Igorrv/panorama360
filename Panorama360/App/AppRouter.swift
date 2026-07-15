import Foundation
import SwiftUI

/// Top-level navigation: onboarding, the project library, capture, stitching,
/// and the tour system. Single source of truth for the current screen via
/// `route`; `captureContext` turns the capture→stitch flow into "add a scene to
/// this project" (nil ⇒ standalone capture, the original behavior).
@MainActor
public final class AppRouter: ObservableObject {

    public enum Route: Equatable {
        case onboarding
        case library
        case capture
        case stitching(PanoramaSession)
        case world(PanoramaSession)
        case viewer(URL)
        case projectDetail(UUID)
        case tourViewer(UUID)

        public static func == (lhs: Route, rhs: Route) -> Bool {
            switch (lhs, rhs) {
            case (.onboarding, .onboarding): return true
            case (.library, .library): return true
            case (.capture, .capture): return true
            case (.stitching(let a), .stitching(let b)): return a.id == b.id
            case (.world(let a), .world(let b)): return a.id == b.id
            case (.viewer(let a), .viewer(let b)): return a == b
            case (.projectDetail(let a), .projectDetail(let b)): return a == b
            case (.tourViewer(let a), .tourViewer(let b)): return a == b
            default: return false
            }
        }
    }

    /// Side-state that flips capture→stitch into "add a scene to this project".
    public struct CaptureContext: Equatable {
        public let projectID: UUID
        public init(projectID: UUID) { self.projectID = projectID }
    }

    @Published public private(set) var route: Route
    @Published public var captureContext: CaptureContext?

    /// Bumped on `goCapture()` so a fresh capture VM is created on return.
    @Published public private(set) var captureGeneration: Int = 0
    @Published public private(set) var tutorialActive: Bool

    /// Project persistence — owned here so the router can commit a captured
    /// scene into a project without bouncing through a view.
    private let projects = ProjectStore()

    private let defaults = UserDefaults.standard
    private let onboardingKey = "panorama360.hasCompletedOnboarding"
    private let tutorialKey = "panorama360.tutorialActive"

    public init() {
        let completed = defaults.bool(forKey: onboardingKey)
        // Home base is now the project library (was: straight to capture).
        route = completed ? .library : .onboarding
        tutorialActive = defaults.bool(forKey: tutorialKey)
    }

    // MARK: - Onboarding transitions

    public func startTutorial() {
        tutorialActive = true
        defaults.set(true, forKey: tutorialKey)
        goCapture()
    }

    /// Skip onboarding to full capture WITHOUT persisting "done" — the crash-loop
    /// guard: if full capture crashes, the next launch returns to onboarding.
    public func skipOnboarding() {
        tutorialActive = false
        defaults.set(false, forKey: tutorialKey)
        goCapture()
    }

    public func goOnboarding() {
        tutorialActive = false
        defaults.set(false, forKey: tutorialKey)
        route = .onboarding
    }

    /// Called after the first room's panorama has been viewed: marks onboarding
    /// done so future launches go to the library. Does not navigate by itself.
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

    public func goWorld(_ session: PanoramaSession) {
        route = .world(session)
    }

    public func goViewer(_ url: URL) {
        route = .viewer(url)
    }

    // MARK: - Library / project routing

    public func goLibrary() { route = .library }

    public func goProjectDetail(_ id: UUID) { route = .projectDetail(id) }

    public func goTourViewer(_ id: UUID) { route = .tourViewer(id) }

    // MARK: - "Add scene" flow (capture → stitch → commit)

    /// Begin capturing a panorama that will become a scene in `projectID`.
    public func beginAddScene(to projectID: UUID) {
        captureContext = CaptureContext(projectID: projectID)
        goCapture()
    }

    /// Cancel an in-flight "add scene" capture — clears context and returns to
    /// the project detail (or library if there's no context).
    public func cancelAddScene() {
        let pid = captureContext?.projectID
        captureContext = nil
        if let pid { goProjectDetail(pid) } else { goLibrary() }
    }

    /// Commit a finished session as a new scene in the active project, then
    /// return to the project detail. No-op if there's no active context.
    public func commitAddScene(session: PanoramaSession) {
        guard let pid = captureContext?.projectID,
              var project = projects.project(id: pid) else { return }
        let scene = TourScene(sessionID: session.id,
                              title: "Cena \(project.scenes.count + 1)")
        project.scenes.append(scene)
        if project.startSceneID == nil { project.startSceneID = scene.id }
        project.updatedAt = Date()
        try? projects.persist(project)
        captureContext = nil
        goProjectDetail(pid)
    }
}
