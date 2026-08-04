import Foundation

/// A navigable link between two `TourScene`s. Placed at a direction (`pitch`,
/// `yaw`) inside the **source** panorama; tapping its marker walks the viewer to
/// `targetSceneID`. Angles are radians in the panorama-local frame, matching
/// `CapturePoint`/`Geometry.sphericalToCartesian`.
public struct Hotspot: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    /// pt-BR label shown on the marker, e.g. "Cozinha".
    public var label: String
    /// SF Symbol name, e.g. "arrow.right.circle.fill".
    public var iconName: String
    /// Placement pitch (radians) in the source panorama.
    public var pitch: Double
    /// Placement yaw (radians) in the source panorama.
    public var yaw: Double
    public var targetSceneID: UUID
    /// Optional pt-BR caption shown under the label (e.g. "12m², reformada").
    /// Optional ⇒ old archives (no key) decode as nil.
    public var info: String?

    public init(id: UUID = UUID(),
                label: String,
                iconName: String = "arrow.right.circle.fill",
                pitch: Double,
                yaw: Double,
                targetSceneID: UUID,
                info: String? = nil) {
        self.id = id
        self.label = label
        self.iconName = iconName
        self.pitch = pitch
        self.yaw = yaw
        self.targetSceneID = targetSceneID
        self.info = info
    }
}
