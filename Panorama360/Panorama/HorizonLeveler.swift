import Foundation
import simd

/// Levels the panorama's horizon.
///
/// Every shot's quaternion is relative to the **first** shot, so whatever tilt
/// the phone had at that instant leaks into the whole equirect: the horizon
/// comes out as a sine wave instead of a straight line — the single most
/// obvious giveaway of an amateur stitch.
///
/// Each sample also carries the gravity vector in its own device frame, so
/// rotating it into the reference frame and averaging recovers where "up"
/// really is. The returned rotation maps that axis back onto +Y.
public enum HorizonLeveler {

    /// Beyond this the fit is more likely wrong than the capture is tilted.
    public static let maxTilt: Float = 30 * .pi / 180
    /// Below this the correction is invisible and not worth the risk.
    public static let minTilt: Float = 0.3 * .pi / 180

    public static let identity = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))

    /// World "up" expressed in the reference (first shot) frame, or `nil` when
    /// too few samples carry a usable gravity reading.
    public static func upAxis(for samples: [CaptureSample]) -> SIMD3<Float>? {
        var sum = SIMD3<Float>.zero
        var used = 0
        for sample in samples {
            let g = sample.gravity
            let length = simd_length(g)
            guard length > 0.5 else { continue }   // zero == never recorded
            sum += sample.quaternion.act(-g / length)
            used += 1
        }
        // A consistent set of unit vectors sums to ≈ `used`; a scattered one
        // (sensor noise, drifting tracking) cancels out and is rejected.
        guard used >= 3, simd_length(sum) > 0.6 * Float(used) else { return nil }
        return simd_normalize(sum)
    }

    /// Rotation to pre-multiply into every sample quaternion so the horizon
    /// lands flat. Identity when unmeasurable, negligible, or implausible.
    public static func correction(for samples: [CaptureSample]) -> simd_quatf {
        guard let up = upAxis(for: samples) else {
            Log.stitch.info("Horizon levelling skipped — no gravity in samples")
            return identity
        }
        let target = SIMD3<Float>(0, 1, 0)
        let angle = acos(min(max(simd_dot(up, target), -1), 1))
        let degrees = angle * 180 / .pi
        guard angle > minTilt else { return identity }
        guard angle < maxTilt else {
            Log.stitch.warning("Horizon tilt \(degrees, privacy: .public)° exceeds limit — skipped")
            return identity
        }
        let axis = simd_cross(up, target)
        guard simd_length(axis) > 1e-5 else { return identity }
        Log.stitch.info("Levelling horizon by \(degrees, privacy: .public)°")
        return simd_quatf(angle: angle, axis: simd_normalize(axis))
    }

    /// Sample orientations with the levelling rotation already applied.
    public static func leveledOrientations(for samples: [CaptureSample]) -> [simd_quatf] {
        let rotation = correction(for: samples)
        return samples.map { simd_mul(rotation, $0.quaternion) }
    }
}
