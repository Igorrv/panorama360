import Foundation

/// How the capture sphere is laid out: which latitude bands to shoot, the yaw
/// spacing within each band, and the desired neighbour overlap.
public struct SphereDistribution: Codable, Equatable, Sendable {
    /// Elevation of each band, radians (+up / -down).
    public var pitchBands: [Double]
    /// Step between consecutive points along a band, radians.
    public var yawStep: Double
    /// Desired horizontal overlap fraction (0..1). Informational for the generator.
    public var overlap: Double
    /// When `true`, add a zenith (+90°) and nadir (−90°) single point.
    public var includePoles: Bool

    public init(pitchBands: [Double], yawStep: Double, overlap: Double, includePoles: Bool = true) {
        self.pitchBands = pitchBands
        self.yawStep = yawStep
        self.overlap = overlap
        self.includePoles = includePoles
    }

    /// Default layout for a real room: 3 bands (−40°/0°/+40°) tuned for the
    /// ultra-wide (~120° FOV), no poles → ~18 points. (The earlier 5-band/60-
    /// point default was far too many for a hand-held first room and made the
    /// overlay/UI churn.) Poles omitted so the user only rotates + tilts mildly.
    public static let `default` = SphereDistribution(
        pitchBands: [40, 0, -40].map { radians($0) },
        yawStep: radians(40),
        overlap: 0.4,
        includePoles: false
    )

    /// Production layout for real-estate scanning: 4 latitude bands (+75°/+40°/
    /// 0°/−40°) tuned for the ultra-wide (~120° FOV) **plus the zenith and nadir
    /// poles** → ~24 points covering the FULL sphere (ceiling + floor included),
    /// so the stitched panorama has no black holes at top/bottom. This is the
    /// route `LiveScanner3DView` opens by default. `.default` is kept unchanged
    /// for the lighter ring used elsewhere.
    public static let realEstate = SphereDistribution(
        pitchBands: [75, 40, 0, -40].map { radians($0) },
        yawStep: radians(45),
        overlap: 0.45,
        includePoles: true
    )

    /// Denser preset (~90–100 points) for higher-quality output.
    public static let dense = SphereDistribution(
        pitchBands: [70, 45, 20, 0, -20, -45, -70].map { radians($0) },
        yawStep: radians(20),
        overlap: 0.5,
        includePoles: true
    )

    /// Tiny preset for the onboarding "first room": a single horizon band, ~8
    /// points, no poles. Completes in a minute or two and lets a first-time
    /// user see the whole capture → stitch → viewer loop succeed end-to-end.
    /// Rotate slowly in place at chest height; no need to tilt up/down.
    public static let tutorial = SphereDistribution(
        pitchBands: [0],
        yawStep: radians(45),
        overlap: 0.4,
        includePoles: false
    )
}
