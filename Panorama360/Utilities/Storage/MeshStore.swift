import Foundation

/// Flat-file store for a project's scanned 3D mesh (`RoomMesh`), mirroring
/// `ProjectStore`'s directory layout (`Documents/Panorama360/projects/<id>/`).
/// The mesh is one file: `<projectID>/mesh.p3dm`. Same default root as
/// `ProjectStore` so the two stores point at the same project folders without
/// coupling — `ProjectStore` owns `project.json`, this owns `mesh.p3dm`.
public final class MeshStore {

    public let rootDirectory: URL

    public init(rootDirectory: URL? = nil) {
        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.rootDirectory = docs.appendingPathComponent("Panorama360", isDirectory: true)
                .appendingPathComponent("projects", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.rootDirectory, withIntermediateDirectories: true)
    }

    private func directory(for id: UUID) -> URL {
        rootDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    public func meshURL(for id: UUID) -> URL {
        directory(for: id).appendingPathComponent("mesh.p3dm")
    }

    public func exists(for id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: meshURL(for: id).path)
    }

    @discardableResult
    public func save(_ mesh: RoomMesh, for id: UUID) throws -> URL {
        let dir = directory(for: id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = meshURL(for: id)
        try mesh.encoded().write(to: url, options: .atomic)
        return url
    }

    public func load(for id: UUID) -> RoomMesh? {
        guard let data = try? Data(contentsOf: meshURL(for: id)) else { return nil }
        return RoomMesh(data: data)
    }

    public func delete(for id: UUID) {
        try? FileManager.default.removeItem(at: meshURL(for: id))
    }
}
