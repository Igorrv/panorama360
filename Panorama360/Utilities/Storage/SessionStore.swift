import Foundation

/// Owns the on-disk layout for panorama sessions under `Documents/Panorama360/`.
public final class SessionStore {
    public let rootDirectory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(rootDirectory: URL? = nil) {
        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.rootDirectory = docs.appendingPathComponent("Panorama360", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.rootDirectory, withIntermediateDirectories: true)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    // MARK: - Layout

    public func sessionDirectory(for id: UUID) -> URL {
        rootDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    public func imagesDirectory(for id: UUID) -> URL {
        sessionDirectory(for: id).appendingPathComponent("images", isDirectory: true)
    }

    public func equirectangularURL(for id: UUID) -> URL {
        sessionDirectory(for: id).appendingPathComponent("panorama.heic")
    }

    /// Creates the session's directories on disk and returns the session root.
    public func makeSessionDirectory(id: UUID) throws -> URL {
        let dir = sessionDirectory(for: id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: imagesDirectory(for: id),
                                                withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Persistence

    @discardableResult
    public func persist(_ session: PanoramaSession) throws -> URL {
        let url = session.directoryURL.appendingPathComponent("session.json")
        let data = try encoder.encode(session)
        try data.write(to: url, options: .atomic)
        return url
    }

    public func loadSession(id: UUID) throws -> PanoramaSession {
        let url = sessionDirectory(for: id).appendingPathComponent("session.json")
        let data = try Data(contentsOf: url)
        return try decoder.decode(PanoramaSession.self, from: data)
    }

    /// Lists all stored sessions, newest first.
    public func allSessions() -> [PanoramaSession] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]) else { return [] }
        return urls.compactMap { dir -> PanoramaSession? in
            let file = dir.appendingPathComponent("session.json")
            guard FileManager.default.fileExists(atPath: file.path),
                  let data = try? Data(contentsOf: file) else { return nil }
            return try? decoder.decode(PanoramaSession.self, from: data)
        }
    }

    /// Removes a session and all of its files.
    public func deleteSession(id: UUID) throws {
        try? FileManager.default.removeItem(at: sessionDirectory(for: id))
    }
}
