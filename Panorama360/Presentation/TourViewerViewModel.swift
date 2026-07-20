import Foundation
import SwiftUI
import simd
import Metal

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
    /// True while a scene's equirect is decoding + uploading off the main thread
    /// during a transition — drives the "Carregando cena..." spinner.
    @Published public var isLoadingScene: Bool = false

    public let projectID: UUID
    private let store = ProjectStore()
    private(set) var renderer: PanoramaRenderer?
    private var transitionTask: Task<Void, Never>?
    private var prewarmTask: Task<Void, Never>?
    /// Speculatively decoded target textures (scene.id → prepared equirect) so a
    /// tap swaps instantly instead of decoding behind the fade. VRAM-bounded.
    private var prewarmCache: [UUID: MTLTexture] = [:]
    private static let prewarmCap = 3
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
        prewarmTargets()
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

    /// Fade-through-black with the equirect decode/upload moved off the main
    /// thread: darken → prepare the next texture behind the veil (bounded by a
    /// 5 s timeout) → swap + reset view → lighten. On timeout/failure the old
    /// scene stays visible and `unavailableNotice` fires.
    private func goTo(index: Int) {
        guard let project, project.scenes.indices.contains(index) else { return }
        let scene = project.scenes[index]
        guard let url = store.equirectURL(for: scene) else {
            unavailableNotice = true
            return
        }
        transitionTask?.cancel()
        prewarmTask?.cancel()
        transitionTask = Task { [weak self] in
            guard let self else { return }
            withAnimation(.easeOut(duration: 0.18)) { self.fadeOpacity = 1 }
            // Let the fade land before the (possibly slow) decode kicks in.
            try? await Task.sleep(nanoseconds: 180_000_000)
            if Task.isCancelled { return }

            // Prewarm hit ⇒ instant swap, no decode stall and no spinner.
            var prepared = self.prewarmCache.removeValue(forKey: scene.id)
            if prepared == nil {
                self.isLoadingScene = true
                prepared = await self.prepareBounded(url: url)
                self.isLoadingScene = false
            }
            if Task.isCancelled { return }

            guard let prepared, let renderer else {
                withAnimation(.easeInOut(duration: 0.2)) { self.fadeOpacity = 0 }
                self.unavailableNotice = true
                return
            }
            self.currentIndex = index
            self.currentScene = scene
            self.draftHotspot = nil
            renderer.loadPrepared(prepared)
            self.engine.yaw = Float(scene.initialYaw)
            self.engine.pitch = Float(scene.initialPitch)
            withAnimation(.easeInOut(duration: 0.24)) { self.fadeOpacity = 0 }
            self.prewarmTargets()   // speculate on this scene's links
        }
    }

    /// Speculatively decodes the current scene's reachable targets off-main so a
    /// later tap swaps instantly. Capped to bound VRAM; cancelled on navigate/detach.
    private func prewarmTargets() {
        prewarmTask?.cancel()
        let sceneID = currentScene?.id
        prewarmTask = Task { [weak self] in
            guard let self, let sceneID, let scene = self.project?.scene(with: sceneID) else { return }
            for h in scene.hotspots where self.targetExists(h) {
                if Task.isCancelled { return }
                if self.prewarmCache[h.targetSceneID] != nil { continue }
                guard let target = self.project?.scene(with: h.targetSceneID),
                      let url = self.store.equirectURL(for: target),
                      let renderer = self.renderer else { continue }
                if self.prewarmCache.count >= Self.prewarmCap,
                   let evict = self.prewarmCache.keys.first {
                    self.prewarmCache.removeValue(forKey: evict)
                }
                if let tex = await renderer.preparePanogram(at: url) {
                    self.prewarmCache[h.targetSceneID] = tex
                }
            }
        }
    }

    /// Runs the off-main texture prepare against a 5 s timeout. First to finish
    /// (prepare or the timeout) wins; the loser is cancelled. Returns the
    /// prepared texture or nil on timeout/failure.
    private func prepareBounded(url: URL) async -> MTLTexture? {
        guard let renderer else { return nil }
        return await withTaskGroup(of: MTLTexture?.self) { group -> MTLTexture? in
            group.addTask { await renderer.preparePanogram(at: url) }
            group.addTask {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                return nil
            }
            // `group.next()` is `MTLTexture??`; unwrap the outer layer — the inner
            // value is the texture (prepare won) or nil (timeout won).
            if let winner = await group.next() {
                group.cancelAll()
                return winner
            }
            group.cancelAll()
            return nil
        }
    }

    /// Cancels any in-flight scene transition — called on view disappear so a
    /// half-finished fade doesn't keep mutating a detached view-model.
    public func detach() {
        transitionTask?.cancel()
        prewarmTask?.cancel()
        prewarmTask = nil
        transitionTask = nil
        prewarmCache.removeAll()
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
            // Vertical-FOV convention — mirrors viewer_vertex (Shaders.metal) so
            // the marker stays glued to its panorama texel at any viewport aspect.
            let (pos, scale) = Geometry.projectOnViewport(
                pointDir: dir, lookDir: look, upHint: upHint,
                verticalFOV: Double(engine.fov),
                aspect: Double(viewportSize.width / max(viewportSize.height, 1)),
                viewport: viewportSize)
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

    public func targetTitle(for h: Hotspot) -> String? {
        project?.scene(with: h.targetSceneID)?.title
    }

    /// True if this hotspot still points at a scene that exists in the project.
    /// Replaces a fragile pt-BR string match — the view decides how to render a
    /// dead target from this boolean.
    public func targetExists(_ h: Hotspot) -> Bool {
        project?.scene(with: h.targetSceneID) != nil
    }
}
