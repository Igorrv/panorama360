import Foundation
import os

/// Flat-file JSON store for `Project` tours, mirroring `SessionStore`'s layout
/// under `Documents/Panorama360/projects/`. Each project is one folder:
/// `<projectID>/project.json`.
///
/// Owns a `SessionStore` reference so it can resolve a `TourScene`'s equirect
/// on demand (`equirectURL(for:)`) — the project never copies or owns the
/// finished panorama; it points at the source session's `panorama.heic`.
public final class ProjectStore {

    public let rootDirectory: URL
    public let sessionStore: SessionStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// In-memory "is this scene's equirect present on disk?" cache, keyed by the
    /// scene's source `sessionID`. `equirectURL(for:)` is queried during tour
    /// navigation and list rendering; a `FileManager.fileExists` round-trip each
    /// time is wasteful. Only **positive** hits are cached: a missing file is
    /// re-probed every call, so a freshly stitched panorama is picked up at once
    /// — important because stitching happens in a separate `StitchingViewModel`
    /// with its own store instance that can't reach this cache. Drop entries
    /// explicitly via `invalidateReadiness`/`invalidateAll` when a panorama is
    /// known to be removed.
    private let readinessCache = OSAllocatedUnfairLock(initialState: [UUID: Bool]())

    public init(rootDirectory: URL? = nil, sessionStore: SessionStore = SessionStore()) {
        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.rootDirectory = docs.appendingPathComponent("Panorama360", isDirectory: true)
                .appendingPathComponent("projects", isDirectory: true)
        }
        self.sessionStore = sessionStore
        try? FileManager.default.createDirectory(at: self.rootDirectory, withIntermediateDirectories: true)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    // MARK: - Layout

    public func projectDirectory(for id: UUID) -> URL {
        rootDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    @discardableResult
    public func makeProjectDirectory(id: UUID) throws -> URL {
        let dir = projectDirectory(for: id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Persistence

    @discardableResult
    public func persist(_ project: Project) throws -> URL {
        try makeProjectDirectory(id: project.id)
        let url = projectDirectory(for: project.id).appendingPathComponent("project.json")
        let data = try encoder.encode(project)
        try data.write(to: url, options: .atomic)
        return url
    }

    public func loadProject(id: UUID) throws -> Project {
        let url = projectDirectory(for: id).appendingPathComponent("project.json")
        let data = try Data(contentsOf: url)
        return try decoder.decode(Project.self, from: data)
    }

    /// Loads a project without throwing (nil if missing/corrupt).
    public func project(id: UUID) -> Project? {
        try? loadProject(id: id)
    }

    /// Lists all stored projects, newest (`updatedAt`) first.
    public func allProjects() -> [Project] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return [] }
        return urls.compactMap { dir -> Project? in
            let file = dir.appendingPathComponent("project.json")
            guard FileManager.default.fileExists(atPath: file.path),
                  let data = try? Data(contentsOf: file) else { return nil }
            return try? decoder.decode(Project.self, from: data)
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func deleteProject(id: UUID) throws {
        try? FileManager.default.removeItem(at: projectDirectory(for: id))
    }

    // MARK: - Scene equirect resolution

    /// The finished equirectangular image URL for a scene's source session, or
    /// nil if the session has no stitched panorama / the file is missing.
    public func equirectURL(for scene: TourScene) -> URL? {
        let url = sessionStore.equirectangularURL(for: scene.sessionID)
        // Fast path: a known-present equirect skips the disk probe entirely.
        if readinessCache.withLock({ $0[scene.sessionID] ?? false }) {
            return url
        }
        // Slow path: probe the disk. Remember only positive hits so a panorama
        // that appears later (stitched by another flow) is seen at once.
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        readinessCache.withLock { $0[scene.sessionID] = true }
        return url
    }

    /// Drops one session's cached readiness. Call when its panorama is deleted or
    /// replaced and this same store instance previously served it as present.
    public func invalidateReadiness(sessionID: UUID) {
        readinessCache.withLock { $0.removeValue(forKey: sessionID) }
    }

    /// Drops the whole readiness cache. Call after a bulk re-stitch or delete.
    public func invalidateAll() {
        readinessCache.withLock { $0.removeAll() }
    }
}
