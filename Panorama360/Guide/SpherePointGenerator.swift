import Foundation

/// Generates capture points for a sphere using latitude-aware density: bands
/// near the poles get fewer points so coverage stays roughly even, and adjacent
/// bands are half-staggered (brick pattern) to improve overlap.
public enum SpherePointGenerator {

    public static func generate(distribution d: SphereDistribution) -> [CapturePoint] {
        var points: [CapturePoint] = []
        var index = 0
        let twoPi = 2.0 * Double.pi

        for (band, pitch) in d.pitchBands.enumerated() {
            let bandRadius = cos(pitch)             // arc fraction vs equator
            guard bandRadius > 0.05 else { continue } // too close to a pole
            let count = max(1, Int((twoPi * bandRadius / d.yawStep).rounded()))
            let step = twoPi / Double(count)
            let offset = band % 2 == 0 ? 0.0 : step / 2

            for j in 0..<count {
                let yaw = Geometry.wrap(Double(j) * step + offset)
                points.append(CapturePoint(index: index, pitch: pitch, yaw: yaw))
                index += 1
            }
        }

        if d.includePoles {
            points.append(CapturePoint(index: index, pitch: .pi / 2, yaw: 0))
            index += 1
            points.append(CapturePoint(index: index, pitch: -.pi / 2, yaw: 0))
        }
        return points
    }
}
