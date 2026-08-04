import Foundation

/// Backs the project detail screen: loads one `Project`, reports per-scene
/// equirect readiness, and deletes scenes. Navigation is bridged by the view
/// (the router is not held here), matching `CaptureViewModel`'s pattern.
@MainActor
public final class ProjectDetailViewModel: ObservableObject {

    @Published public private(set) var project: Project?
    public let projectID: UUID
    private let store = ProjectStore()
    private let meshStore = MeshStore()

    public init(projectID: UUID) {
        self.projectID = projectID
        reload()
    }

    public func reload() {
        project = store.project(id: projectID)
    }

    /// True if at least one scene has a stitched equirect on disk.
    public var canStartTour: Bool {
        project?.scenes.contains(where: { equirectReady($0) }) ?? false
    }

    /// True if this project has a saved LiDAR 3D mesh to walk through.
    public var meshReady: Bool { meshStore.exists(for: projectID) }

    /// The scene the tour should open on (first ready scene).
    public func startScene() -> TourScene? {
        guard let project else { return nil }
        if let id = project.startSceneID,
           let s = project.scene(with: id), equirectReady(s) { return s }
        return project.scenes.first { equirectReady($0) }
    }

    public func equirectReady(_ scene: TourScene) -> Bool {
        store.equirectURL(for: scene) != nil
    }

    public func deleteScene(_ scene: TourScene) {
        guard var project else { return }
        project.scenes.removeAll { $0.id == scene.id }
        if project.startSceneID == scene.id {
            project.startSceneID = project.scenes.first?.id
        }
        project.updatedAt = Date()
        try? store.persist(project)
        reload()
    }

    /// Persists per-project branding (accent + broker identity). Blank text
    /// fields collapse to nil so empty branding simply hides in the tour.
    public func updateBranding(accentHex: String?,
                               brokerName: String?,
                               brokerContact: String?) {
        guard var project else { return }
        project.accentHex = accentHex
        project.brokerName = clean(brokerName)
        project.brokerContact = clean(brokerContact)
        project.updatedAt = Date()
        try? store.persist(project)
        reload()
    }

    /// Trims whitespace and returns nil for empty strings (keeps archives tidy).
    private func clean(_ text: String?) -> String? {
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}
