import Foundation
import simd
import SwiftUI

/// Where the centre reticle is relative to its target.
public enum ReticleState: Sendable, Equatable {
    case far      // white
    case near     // yellow
    case aligned  // green — capture gate evaluates
}

/// A point prepared for overlay rendering.
public struct OverlayPoint: Identifiable, Hashable {
    public let id: UUID
    public let position: CGPoint?   // nil = behind camera
    public let scale: CGFloat
    public let state: CapturePointState
    public let confidence: Double
    public let captured: Bool
}

/// Summary of the current alignment target.
public struct AlignmentInfo: Equatable {
    public let pointID: UUID?
    public let angularDistance: Double   // radians
    public let confidence: Double        // 0..1
    public let state: CapturePointState
}

/// Holds the sphere of capture points and computes per-frame alignment + overlay
/// positions. `@MainActor` because it backs SwiftUI.
@MainActor
public final class CaptureGuide: ObservableObject {

    @Published public private(set) var points: [CapturePoint]
    @Published public private(set) var overlayPoints: [OverlayPoint] = []
    @Published public private(set) var alignment = AlignmentInfo(pointID: nil,
                                                                  angularDistance: .greatestFiniteMagnitude,
                                                                  confidence: 0,
                                                                  state: .idle)
    @Published public private(set) var reticle: ReticleState = .far
    @Published public private(set) var orientation: DeviceOrientation?
    @Published public private(set) var capturedCount: Int = 0
    /// Bumped on each capture to trigger pulse animations.
    @Published public private(set) var capturePulse: Int = 0

    public let thresholds: AlignmentThresholds
    public let distribution: SphereDistribution

    public var viewport: CGSize = .zero
    public var horizontalFOV: Double = radians(62)

    private var directions: [SIMD3<Float>] = []

    public init(distribution: SphereDistribution = .default,
                thresholds: AlignmentThresholds = .default) {
        self.distribution = distribution
        self.thresholds = thresholds
        self.points = SpherePointGenerator.generate(distribution: distribution)
        self.directions = points.map { Geometry.sphericalToCartesian(pitch: $0.pitch, yaw: $0.yaw) }
    }

    public var totalPoints: Int { points.count }
    public var fractionComplete: Double { points.fractionComplete }

    // MARK: - Per-frame update

    public func update(orientation: DeviceOrientation) {
        self.orientation = orientation
        let look = orientation.lookDirection
        let up = orientation.quaternion.act(SIMD3<Float>(0, 1, 0))

        // 1. Nearest un-captured point (angular distance via dot products).
        var bestDist: Float = .greatestFiniteMagnitude
        var bestIndex: Int? = nil
        for (i, p) in points.enumerated() where !p.isCaptured {
            let d = Geometry.angularDistance(directions[i], look)
            if d < bestDist { bestDist = d; bestIndex = i }
        }

        // 2. Alignment info + reticle.
        if let i = bestIndex {
            let dist = Double(bestDist)
            let state = thresholds.state(forDistance: dist)
            let conf = proximityConfidence(distance: dist)
            alignment = AlignmentInfo(pointID: points[i].id,
                                      angularDistance: dist,
                                      confidence: conf,
                                      state: state)
            reticle = reticleState(for: state)
        } else {
            alignment = AlignmentInfo(pointID: nil, angularDistance: 0, confidence: 1, state: .captured)
            reticle = .aligned
        }

        // 3. Overlay positions for all points.
        rebuildOverlay(look: look, up: up, nearest: bestIndex)
    }

    // MARK: - Capture side-effects

    /// Marks a point captured. Called by the VM after a successful photo save.
    public func markCaptured(pointID: UUID) {
        guard let idx = points.firstIndex(where: { $0.id == pointID }) else { return }
        guard !points[idx].isCaptured else { return }
        points[idx].state = .captured
        points[idx].confidence = 1
        points[idx].revision += 1
        capturedCount = points.capturedCount
        capturePulse &+= 1
    }

    public func reset(with distribution: SphereDistribution? = nil) {
        let d = distribution ?? self.distribution
        points = SpherePointGenerator.generate(distribution: d)
        directions = points.map { Geometry.sphericalToCartesian(pitch: $0.pitch, yaw: $0.yaw) }
        overlayPoints = []
        alignment = AlignmentInfo(pointID: nil, angularDistance: .greatestFiniteMagnitude, confidence: 0, state: .idle)
        reticle = .far
        capturedCount = 0
    }

    // MARK: - Helpers

    private func rebuildOverlay(look: SIMD3<Float>, up: SIMD3<Float>, nearest: Int?) {
        guard viewport.width > 1 else { return }
        var result: [OverlayPoint] = []
        result.reserveCapacity(points.count)
        for (i, p) in points.enumerated() {
            let (pos, scale) = Geometry.projectOnViewport(
                pointDir: directions[i], lookDir: look, upHint: up,
                horizontalFOV: horizontalFOV, viewport: viewport)
            let isNearest = (i == nearest)
            let proximityState: CapturePointState = isNearest ? alignment.state : .idle
            let state: CapturePointState = p.isCaptured ? .captured : proximityState
            let conf: Double = p.isCaptured ? 1 : (isNearest ? alignment.confidence : 0)
            result.append(OverlayPoint(id: p.id, position: pos, scale: scale,
                                       state: state, confidence: conf, captured: p.isCaptured))
        }
        overlayPoints = result
    }

    /// 0..1 confidence rising as the device closes on the target.
    private func proximityConfidence(distance: Double) -> Double {
        let near = thresholds.nearDistance
        if distance <= thresholds.alignedDistance { return 1 }
        let t = (near - distance) / (near - thresholds.alignedDistance)
        return max(0, min(1, t))
    }

    private func reticleState(for pointState: CapturePointState) -> ReticleState {
        switch pointState {
        case .aligned: return .aligned
        case .near:    return .near
        default:       return .far
        }
    }
}
