import Foundation

/// Backs the project detail screen: loads one `Project`, reports per-scene
/// equirect readiness, and deletes scenes. Navigation is bridged by the view
/// (the router is not held here), matching `CaptureViewModel`'s pattern.
@MainActor
public final class ProjectDetailViewModel: ObservableObject {

    @Published public private(set) var project: Project?
    public let projectID: UUID
    private let store = ProjectStore()

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
}
