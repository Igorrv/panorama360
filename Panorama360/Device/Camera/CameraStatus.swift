import AVFoundation

/// Snapshot of the camera's focus/exposure state, read on demand for the gate.
public struct CameraStatus: Sendable {
    public let isAdjustingFocus: Bool
    public let isAdjustingExposure: Bool
    public let isAdjustingWhiteBalance: Bool
    public let exposureTargetOffset: Float
    public let lensAperture: Float
    public let iso: Float
    public let exposureDuration: Double

    public init(isAdjustingFocus: Bool,
                isAdjustingExposure: Bool,
                isAdjustingWhiteBalance: Bool,
                exposureTargetOffset: Float,
                lensAperture: Float,
                iso: Float,
                exposureDuration: Double) {
        self.isAdjustingFocus = isAdjustingFocus
        self.isAdjustingExposure = isAdjustingExposure
        self.isAdjustingWhiteBalance = isAdjustingWhiteBalance
        self.exposureTargetOffset = exposureTargetOffset
        self.lensAperture = lensAperture
        self.iso = iso
        self.exposureDuration = exposureDuration
    }

    /// True when focus, exposure and white balance have all settled.
    public var isSettled: Bool {
        !isAdjustingFocus && !isAdjustingExposure && !isAdjustingWhiteBalance
    }

    public static let unknown = CameraStatus(isAdjustingFocus: true,
                                             isAdjustingExposure: true,
                                             isAdjustingWhiteBalance: true,
                                             exposureTargetOffset: 0,
                                             lensAperture: 0,
                                             iso: 0,
                                             exposureDuration: 0)
}

extension CameraStatus {
    /// Reads the current status from a configured capture device. Must be called
    /// on a background queue if device access is contested.
    public static func current(from device: AVCaptureDevice?) -> CameraStatus {
        guard let device else { return .unknown }
        return CameraStatus(
            isAdjustingFocus: device.isAdjustingFocus,
            isAdjustingExposure: device.isAdjustingExposure,
            isAdjustingWhiteBalance: device.isAdjustingWhiteBalance,
            exposureTargetOffset: device.exposureTargetBiasOffsets.targetOffset,
            lensAperture: device.lensAperture,
            iso: device.iso,
            exposureDuration: device.exposureDuration.seconds
        )
    }
}
