import Foundation
import SwiftUI
import simd

/// Drives the multi-scene tour: owns a `ViewerEngine` + the active `PanoramaRenderer`,
/// manages the current scene, performs fade-through-black transitions by swapping
/// the renderer's equirect, projects hotspots onto the viewport for the overlay,
/// and authors hotspots in edit mode. Persists hotspot edits via `ProjectStore`.
@MainActor
public final class TourViewerViewModel: ObservableObject {

    public let engine = ViewerEngine()
    @Published public private(set) var project: Project?
    @Published public private(set) var currentScene: TourScene?
    @Published public private(set) var currentIndex: Int = 0
    @Published public var fadeOpacity: Double = 0
    @Published public var editMode: Bool = false
    @Published public var draftHotspot: Hotspot?
    @Published public var showLinkSheet: Bool = false
    @Published public var unavailableNotice: Bool = false

    public let projectID: UUID
    private let store = ProjectStore()
    private(set) var renderer: PanoramaRenderer?
    public private(set) var viewportSize: CGSize = .zero

    public init(projectID: UUID) {
        self.projectID = projectID
        reload()
    }

    public func reload() {
        project = store.project(id: projectID)
        if currentScene == nil { currentScene = project?.entryScene }
        if let cur = currentScene {
            currentIndex = project?.scenes.firstIndex(where: { $0.id == cur.id }) ?? 0
        }
    }

    // MARK: - Metal wiring

    public func attach(renderer: PanoramaRenderer) {
        self.renderer = renderer
        loadCurrentScene()
    }

    public func updateAspect(_ size: CGSize) {
        viewportSize = size
        engine.updateAspect(size)
    }

    /// The equirect URL for the initial Metal load (entry scene).
    public func initialURL() -> URL? {
        let scene = project?.entryScene ?? project?.scenes.first
        guard let scene else { return nil }
        return store.equirectURL(for: scene)
    }

    private func loadCurrentScene() {
        guard let renderer, let scene = currentScene,
              let url = store.equirectURL(for: scene) else { return }
        engine.yaw = Float(scene.initialYaw)
        engine.pitch = Float(scene.initialPitch)
        renderer.loadPanogram(at: url)
    }

    // MARK: - Scene navigation

    public func next() {
        guard let project else { return }
        guard !project.scenes.isEmpty else { return }
        goTo(index: (currentIndex + 1) % project.scenes.count)
    }

    public func previous() {
        guard let project else { return }
        guard !project.scenes.isEmpty else { return }
        goTo(index: (currentIndex - 1 + project.scenes.count) % project.scenes.count)
    }

    public func transition(to sceneID: UUID) {
        guard let project,
              let idx = project.scenes.firstIndex(where: { $0.id == sceneID }) else { return }
        goTo(index: idx)
    }

    /// Fade-through-black: darken, swap equirect + reset view, then lighten.
    private func goTo(index: Int) {
        guard let project, project.scenes.indices.contains(index) else { return }
        let scene = project.scenes[index]
        guard store.equirectURL(for: scene) != nil else {
            unavailableNotice = true
            return
        }
        Task {
            withAnimation(.easeOut(duration: 0.18)) { fadeOpacity = 1 }
            try? await Task.sleep(nanoseconds: 180_000_000)
            currentIndex = index
            currentScene = scene
            draftHotspot = nil
            loadCurrentScene()
            withAnimation(.easeInOut(duration: 0.24)) { fadeOpacity = 0 }
        }
    }

    // MARK: - Hotspot projection (consumed by the overlay)

    public struct ProjectedHotspot: Identifiable {
        public let id: UUID
        public let hotspot: Hotspot
        public let position: CGPoint?
        public let scale: CGFloat
    }

    /// Projects the current scene's hotspots into viewport coordinates using the
    /// engine's live look direction. Same math `CaptureOverlay` uses for guide
    /// points. Empty until the viewport size is known.
    public func projectedHotspots() -> [ProjectedHotspot] {
        guard viewportSize.width > 1, let scene = currentScene else { return [] }
        let look = Geometry.sphericalToCartesianf(pitch: Double(engine.pitch),
                                                  yaw: Double(engine.yaw))
        let upHint = SIMD3<Float>(0, 1, 0)
        return scene.hotspots.map { h in
            let dir = Geometry.sphericalToCartesianf(pitch: h.pitch, yaw: h.yaw)
            let (pos, scale) = Geometry.projectOnViewport(
                pointDir: dir, lookDir: look, upHint: upHint,
                horizontalFOV: Double(engine.fov), viewport: viewportSize)
            return ProjectedHotspot(id: h.id, hotspot: h, position: pos, scale: scale)
        }
    }

    // MARK: - Edit mode (hotspot authoring)

    /// Drop a hotspot at the current look direction (engine pitch/yaw ARE the
    /// panorama-local placement — no inverse math needed).
    public func beginAddHotspot() {
        draftHotspot = Hotspot(label: "Novo link",
                               pitch: Double(engine.pitch),
                               yaw: Double(engine.yaw),
                               targetSceneID: currentScene?.id ?? UUID())
        showLinkSheet = true
    }

    public func cancelHotspot() {
        draftHotspot = nil
        showLinkSheet = false
    }

    public func commitHotspot(targetSceneID: UUID, label: String, icon: String) {
        guard var draft = draftHotspot,
              var project,
              let sceneIdx = project.scenes.firstIndex(where: { $0.id == currentScene?.id }) else { return }
        draft.label = label
        draft.iconName = icon
        draft.targetSceneID = targetSceneID
        project.scenes[sceneIdx].hotspots.append(draft)
        project.updatedAt = Date()
        try? store.persist(project)
        self.project = project
        currentScene = project.scenes[sceneIdx]
        draftHotspot = nil
        showLinkSheet = false
    }

    public func deleteHotspot(id: UUID) {
        guard var project,
              let sceneIdx = project.scenes.firstIndex(where: { $0.id == currentScene?.id }) else { return }
        project.scenes[sceneIdx].hotspots.removeAll { $0.id == id }
        project.updatedAt = Date()
        try? store.persist(project)
        self.project = project
        currentScene = project.scenes[sceneIdx]
    }

    public func otherScenes() -> [TourScene] {
        guard let project, let cur = currentScene else { return [] }
        return project.scenes.filter { $0.id != cur.id }
    }

    public func targetTitle(for h: Hotspot) -> String {
        project?.scene(with: h.targetSceneID)?.title ?? "Cena removida"
    }
}
