import Foundation

/// A virtual tour: an ordered list of `TourScene`s (panoramas) linked by
/// `Hotspot`s. This is the top-level unit a user creates, browses, and (in
/// later phases) syncs to the cloud. Persisted by `ProjectStore` as flat JSON.
public struct Project: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    /// pt-BR title, e.g. "Apartamento - Cobertura".
    public var title: String
    public var scenes: [TourScene]
    /// Scene to open first when playing the tour. Defaults to the first scene.
    public var startSceneID: UUID?
    public let createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(),
                title: String,
                scenes: [TourScene] = [],
                startSceneID: UUID? = nil,
                createdAt: Date = Date(),
                updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.scenes = scenes
        self.startSceneID = startSceneID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// The scene the tour opens on, falling back to the first scene.
    public var entryScene: TourScene? {
        if let id = startSceneID, let s = scenes.first(where: { $0.id == id }) {
            return s
        }
        return scenes.first
    }

    public func scene(with id: UUID) -> TourScene? {
        scenes.first { $0.id == id }
    }
}
