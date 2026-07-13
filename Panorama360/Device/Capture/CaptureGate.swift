import Foundation

/// Inputs to the auto-capture decision.
public struct CaptureGateInput: Sendable {
    public let angularDistanceToTarget: Double   // radians
    public let stability: Stability
    public let cameraStatus: CameraStatus
    public let sharpness: Float                  // Laplacian-variance score
    public let cooldownElapsed: Bool
    public let hasTarget: Bool                   // an un-captured aligned point exists

    public init(angularDistanceToTarget: Double,
                stability: Stability,
                cameraStatus: CameraStatus,
                sharpness: Float,
                cooldownElapsed: Bool,
                hasTarget: Bool) {
        self.angularDistanceToTarget = angularDistanceToTarget
        self.stability = stability
        self.cameraStatus = cameraStatus
        self.sharpness = sharpness
        self.cooldownElapsed = cooldownElapsed
        self.hasTarget = hasTarget
    }
}

/// Result of evaluating the gate: whether to fire now, and why/why not.
public struct CaptureGateOutput: Sendable, Equatable {
    public let ready: Bool
    public let blockers: [Blocker]

    public enum Blocker: String, Sendable {
        case noTarget        = "No point aligned"
        case notAligned      = "Not aligned"
        case moving          = "Device moving"
        case adjustingFocus  = "Focusing"
        case adjustingExposure = "Setting exposure"
        case blurry          = "Image blurry"
        case cooldown        = "Just captured"
    }

    public init(ready: Bool, blockers: [Blocker]) {
        self.ready = ready
        self.blockers = blockers
    }
}

/// Stateless auto-capture gate. All thresholds are tunable.
public struct CaptureGate: Sendable {
    public var alignedDistance: Double       // radians, max acceptable off-target
    public var minSharpness: Float           // Laplacian-variance floor
    public var minStability: Double          // 0..1 stability score floor
    public var requireFocusSettled: Bool
    public var requireExposureSettled: Bool

    public init(alignedDistance: Double = radians(4.5),
                minSharpness: Float = 25,
                minStability: Double = 0.72,
                requireFocusSettled: Bool = true,
                requireExposureSettled: Bool = true) {
        self.alignedDistance = alignedDistance
        self.minSharpness = minSharpness
        self.minStability = minStability
        self.requireFocusSettled = requireFocusSettled
        self.requireExposureSettled = requireExposureSettled
    }

    public func evaluate(_ input: CaptureGateInput) -> CaptureGateOutput {
        var blockers: [CaptureGateOutput.Blocker] = []

        guard input.hasTarget else {
            return CaptureGateOutput(ready: false, blockers: [.noTarget])
        }
        if input.angularDistanceToTarget > alignedDistance      { blockers.append(.notAligned) }
        if input.stability.score < minStability                 { blockers.append(.moving) }
        if requireFocusSettled && input.cameraStatus.isAdjustingFocus { blockers.append(.adjustingFocus) }
        if requireExposureSettled && input.cameraStatus.isAdjustingExposure { blockers.append(.adjustingExposure) }
        if input.sharpness > 0, input.sharpness < minSharpness  { blockers.append(.blurry) }
        if !input.cooldownElapsed                               { blockers.append(.cooldown) }

        return CaptureGateOutput(ready: blockers.isEmpty, blockers: blockers)
    }
}
