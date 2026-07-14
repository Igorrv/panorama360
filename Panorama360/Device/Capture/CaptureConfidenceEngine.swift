import Foundation

/// Blends the raw gate signals into a single 0..1 "capture confidence" for the
/// UI ring, and maps a confidence band to a short Portuguese hint label.
///
/// This is a pure, stateless façade over the signals `CaptureGate` already
/// consumes — it does not re-evaluate the gate. The view-model calls it each
/// evaluation tick to drive the on-screen confidence ring + the status line.
public enum CaptureConfidenceEngine {

    /// - Parameters:
    ///   - alignment: 0..1 proximity to the active target (`AlignmentInfo.confidence`).
    ///   - stability: 0..1 stillness (`Stability.score`).
    ///   - sharpness: Laplacian-variance sharpness from the camera (≈0..hundreds).
    ///   - minSharpness: the gate's sharpness threshold; anything at/above 2× this is "fully sharp".
    public static func combine(alignment: Double,
                               stability: Double,
                               sharpness: Float,
                               minSharpness: Float) -> Float {
        let a = Float(clamped: alignment, unit: 0...1)
        let s = Float(clamped: stability, unit: 0...1)
        let denom = max(minSharpness * 2, 1)
        let sh = max(0, min(1, sharpness / denom))
        // Alignment dominates (you must be on target); stability matters; sharpness gates.
        return max(0, min(1, 0.55 * a + 0.30 * s + 0.15 * sh))
    }
}

private extension Float {
    init(clamped value: Double, unit range: ClosedRange<Double>) {
        self = Float(min(max(value, range.lowerBound), range.upperBound))
    }
}
