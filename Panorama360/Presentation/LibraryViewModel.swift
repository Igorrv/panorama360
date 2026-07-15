import Foundation

/// Backs the project library: lists, creates, and deletes `Project` tours via
/// `ProjectStore`. Thin by design — the router owns navigation.
@MainActor
public final class LibraryViewModel: ObservableObject {

    @Published public private(set) var projects: [Project] = []
    private let store = ProjectStore()

    public init() {}

    /// Refresh from disk (newest first).
    public func reload() {
        projects = store.allProjects()
    }

    /// Creates a project, persists it, and returns its id (nil on failure).
    @discardableResult
    public func createProject(title: String) -> UUID? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = Project(title: trimmed.isEmpty ? "Novo projeto" : trimmed)
        do {
            try store.persist(project)
            reload()
            return project.id
        } catch {
            return nil
        }
    }

    public func deleteProject(_ project: Project) {
        try? store.deleteProject(id: project.id)
        reload()
    }
}
