import Foundation

/// One virtual capture point on the panorama sphere.
///
/// Each point owns an absolute target direction in spherical coordinates
/// (`pitch` = elevation, `yaw` = heading), plus mutable alignment state.
public struct CapturePoint: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let index: Int          // ordering for sequential guidance
    public let pitch: Double       // radians, +up / -down
    public let yaw: Double         // radians, 0..2π around the horizon

    public var state: CapturePointState
    /// 0..1 alignment confidence while `near`/`aligned`; drives scale + glow.
    public var confidence: Double
    /// Monotonic counter bumped on each state change (used by diffing/animation).
    public var revision: Int

    public init(id: UUID = UUID(), index: Int, pitch: Double, yaw: Double) {
        self.id = id
        self.index = index
        self.pitch = pitch
        self.yaw = yaw
        self.state = .idle
        self.confidence = 0
        self.revision = 0
    }

    public var isCaptured: Bool { state == .captured }
}

public extension Array where Element == CapturePoint {
    /// First point that has not yet been captured (the current guidance target).
    var nextUncaptured: CapturePoint? {
        first { !$0.isCaptured }
    }

    var capturedCount: Int { filter(\.isCaptured).count }

    var fractionComplete: Double {
        guard !isEmpty else { return 0 }
        return Double(capturedCount) / Double(count)
    }
}
