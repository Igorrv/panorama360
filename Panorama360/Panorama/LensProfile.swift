import Foundation

/// Brown–Conrady radial distortion coefficients for a device lens, in
/// focal-length-normalised image coordinates (x=(u−cx)/fx). `k1` dominates
/// (barrel for negative values, as on phone ultra-wides); k2/k3 refine the
/// periphery. Applied by `Undistorter` as an inverse-map Metal pass.
public struct LensProfile: Equatable, Sendable {
    public let k1: Float
    public let k2: Float
    public let k3: Float

    public init(k1: Float, k2: Float, k3: Float = 0) {
        self.k1 = k1; self.k2 = k2; self.k3 = k3
    }

    /// All-zero ⇒ no distortion. The safe default for any lens we have not
    /// characterised: undistortion is skipped, so output is never worse than the
    /// raw lens.
    public static let identity = LensProfile(k1: 0, k2: 0, k3: 0)

    public var isIdentity: Bool { k1 == 0 && k2 == 0 && k3 == 0 }
}

/// Per-lens distortion table. Apple does not expose rear-camera radial
/// distortion on most devices (no `cameraCalibrationData` without LiDAR /
/// TrueDepth), so these are measured approximations. **Unknown or non-ultra-wide
/// lenses return `.identity`** — undistortion is skipped, never making things
/// worse. Coefficients are TUNABLE: refine k1 after the first real-device build.
public enum LensProfileTable {

    /// Rear ultra-wide (0.5×, ~120° FOV) — strong barrel distortion corrected by
    /// a small positive k2 at the periphery. Starting values; tune on device.
    private static let ultraWide = LensProfile(k1: -0.12, k2: 0.004, k3: 0.0)

    /// Returns the profile for the lens actually in use. Only the ultra-wide
    /// carries a correction today; the plain wide and any unknown lens return
    /// `.identity`. Gated by a global kill-switch.
    public static func profile(isUltraWide: Bool) -> LensProfile {
        guard enabled else { return .identity }
        return isUltraWide ? ultraWide : .identity
    }

    /// Global kill-switch: env `PANORAMA_DISABLE_UNDISTORT=1` forces `.identity`
    /// everywhere (A/B testing / emergency revert). Defaults on.
    private static let enabled: Bool = {
        ProcessInfo.processInfo.environment["PANORAMA_DISABLE_UNDISTORT"] == nil
    }()
}
