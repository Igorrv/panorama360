import Foundation
import simd

/// Coverage-aware, **dynamic** target generator for the spatial-scanner mode.
///
/// Instead of a fixed sphere of points (see `SpherePointGenerator` / the
/// `.tutorial` distribution), the scanner fills the sphere one photo at a time:
/// after each capture the analyzer marks that direction as "covered" and returns
/// the next target as the centre of the largest remaining uncovered gap. The
/// capture loop therefore has **no fixed point count** — it runs until coverage
/// crosses `minCoverage` (or the user taps Finish).
///
/// Pure value type: `mark` mutates a copy, so it composes cleanly inside the
/// `@MainActor` view-model.
public struct CoverageAnalyzer {

    /// One candidate cell on the sphere to fill.
    private struct Cell {
        let pitch: Double
        let yaw: Double
        let direction: simd_double3
        let weight: Double          // ≈ cos(pitch): poles cover less area
        var covered: Bool
    }

    /// Lens half field-of-view (radians) — the radius each photo covers.
    public let halfFOV: Double
    /// Overlap fraction (0..1). Effective coverage radius = halfFOV × (1 − overlap).
    public let overlap: Double
    /// Coverage fraction at which the scan is considered complete.
    public let minCoverage: Double

    private var cells: [Cell]
    private(set) var capturedDirs: [simd_double3] = []

    /// Weighted covered area / total area (0..1).
    public private(set) var coverageFraction: Double = 0

    public var isComplete: Bool { coverageFraction >= minCoverage }

    /// Default pitch bands: a horizon-heavy layout (where a room's walls are),
    /// with a band above and below for ceiling/floor hints.
    public static var defaultPitchBands: [Double] {
        [radians(45), radians(20), 0, radians(-20), radians(-45)]
    }

    public init(halfFOV: Double,
                pitchBands: [Double] = CoverageAnalyzer.defaultPitchBands,
                yawStep: Double = radians(30),
                overlap: Double = 0.3,
                minCoverage: Double = 0.92) {
        self.halfFOV = halfFOV
        self.overlap = overlap
        self.minCoverage = minCoverage
        self.cells = Self.buildGrid(pitchBands: pitchBands, yawStep: yawStep)
        recomputeCoverage()
    }

    // MARK: - Mutation

    /// Record a freshly captured direction (pitch/yaw, radians, session-local).
    public mutating func mark(pitch: Double, yaw: Double) {
        let dir = Geometry.sphericalToCartesian(pitch: pitch, yaw: yaw)
        capturedDirs.append(dir)
        recomputeCoverage()
    }

    /// The next target is the **uncovered cell nearest the user's current look
    /// direction**. This keeps the dot just ahead of the user as they sweep
    /// around (guided feel) instead of leaping to the biggest hole on the far
    /// side of the sphere. Returns `nil` when the sphere is covered.
    ///
    /// `currentLook` is the device's forward direction in the session-local
    /// frame (e.g. `DeviceOrientation.lookDirection` cast to double).
    public func nextTarget(currentLook: SIMD3<Double>) -> (pitch: Double, yaw: Double)? {
        guard !cells.isEmpty else { return nil }
        let look = simd_normalize(currentLook)
        let best = cells
            .filter { !$0.covered }
            .min(by: { a, b in
                let da = Self.angularDistance(a.direction, look)
                let db = Self.angularDistance(b.direction, look)
                if da != db { return da < db }
                // Deterministic tie-break.
                if a.pitch != b.pitch { return a.pitch < b.pitch }
                return a.yaw < b.yaw
            })
        return best.map { ($0.pitch, $0.yaw) }
    }

    public var capturedCount: Int { capturedDirs.count }

    // MARK: - Internals

    private var effectiveRadius: Double { halfFOV * (1 - overlap) }

    private mutating func recomputeCoverage() {
        let radius = effectiveRadius
        var coveredWeight = 0.0
        var totalWeight = 0.0
        for i in cells.indices {
            cells[i].covered = minDistanceToCaptured(cells[i].direction) <= radius
            totalWeight += cells[i].weight
            if cells[i].covered { coveredWeight += cells[i].weight }
        }
        coverageFraction = totalWeight > 0 ? coveredWeight / totalWeight : 0
    }

    private func minDistanceToCaptured(_ dir: simd_double3) -> Double {
        var best = Double.greatestFiniteMagnitude
        for c in capturedDirs {
            let d = Self.angularDistance(dir, c)
            if d < best { best = d }
        }
        return best
    }

    private static func angularDistance(_ a: simd_double3, _ b: simd_double3) -> Double {
        let dot = simd_clamp(simd_dot(simd_normalize(a), simd_normalize(b)), -1, 1)
        return acos(dot)
    }

    private static func buildGrid(pitchBands: [Double], yawStep: Double) -> [Cell] {
        var cells: [Cell] = []
        let twoPi = 2.0 * Double.pi
        for pitch in pitchBands {
            let bandRadius = cos(pitch)
            guard bandRadius > 0.08 else { continue }   // skip the very poles
            let count = max(1, Int((twoPi * bandRadius / yawStep).rounded()))
            let step = twoPi / Double(count)
            let offset = cells.count % 2 == 0 ? 0.0 : step / 2   // half-stagger bands
            for j in 0..<count {
                let yaw = Geometry.wrap(Double(j) * step + offset)
                let dir = Geometry.sphericalToCartesian(pitch: pitch, yaw: yaw)
                cells.append(Cell(pitch: pitch, yaw: yaw, direction: dir,
                                  weight: bandRadius, covered: false))
            }
        }
        return cells
    }
}
