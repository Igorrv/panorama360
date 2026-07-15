import Foundation

/// One panorama within a `Project` tour. Named `TourScene` (not `Scene`) to
/// avoid shadowing `SwiftUI.Scene` / `SCNScene`.
///
/// The equirectangular image is **never copied or stored here** — only the
/// source `sessionID` is kept, and the finished panorama (`panorama.heic`) is
/// resolved on demand via `ProjectStore.equirectURL(for:)`. Deleting a scene
/// therefore leaves the underlying `PanoramaSession` intact (no data loss).
public struct TourScene: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    /// The `PanoramaSession.id` whose stitched equirect this scene shows.
    public var sessionID: UUID
    /// pt-BR title, e.g. "Sala".
    public var title: String
    /// Initial view direction when the scene loads (radians).
    public var initialPitch: Double
    public var initialYaw: Double
    public var hotspots: [Hotspot]
    public let createdAt: Date

    public init(id: UUID = UUID(),
                sessionID: UUID,
                title: String,
                initialPitch: Double = 0,
                initialYaw: Double = 0,
                hotspots: [Hotspot] = [],
                createdAt: Date = Date()) {
        self.id = id
        self.sessionID = sessionID
        self.title = title
        self.initialPitch = initialPitch
        self.initialYaw = initialYaw
        self.hotspots = hotspots
        self.createdAt = createdAt
    }
}
