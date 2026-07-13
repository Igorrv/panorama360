import Foundation
import CoreImage

/// Lens undistortion pass.
///
/// **v1 note:** phone lenses are very close to rectilinear over the central
/// field of view, and ARKit/AVFoundation don't expose radial distortion for the
/// rear wide camera (only LiDAR/TrueDepth devices ship `cameraCalibrationData`).
/// So by default `k1`/`k2` are `0` and this is a no-op pass-through. The plumbing
/// is here so a calibrated model (or the OpenCV path) can be dropped in.
public enum LensUndistortion {

    /// Returns a (possibly undistorted) `CIImage` for `sample`. No-op when the
    /// distortion coefficients are zero.
    public static func process(_ image: CIImage, intrinsics: CameraIntrinsics) -> CIImage {
        guard intrinsics.k1 != 0 || intrinsics.k2 != 0 else { return image }
        // A light, approximate barrel/pincushion using Core Image when calibration
        // is available. Scale the amount from k1.
        let filter = CIFilter(name: "CIBumpDistortion")
        filter?.setValue(image, forKey: kCIInputImageKey)
        filter?.setValue(CIVector(x: image.extent.midX, y: image.extent.midY),
                         forKey: kCIInputCenterKey)
        filter?.setValue(image.extent.width / 2, forKey: kCIInputRadiusKey)
        filter?.setValue(-Float(intrinsics.k1) * 200.0, forKey: kCIInputScaleKey)
        return filter?.outputImage ?? image
    }
}
