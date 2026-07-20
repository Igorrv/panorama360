import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins

/// Streaming exposure tracker for the live globe: keeps an EMA of the mean
/// luminance of captured photos and returns a per-photo gain so each new tile
/// matches the globe's running brightness — the live analogue of
/// `ExposureCompensator`, but one photo at a time (smoothed) so the globe never
/// pops as lighting shifts during a scan. Clamp range matches the stitcher's
/// compensator (0.6…1.8).
public final class LiveExposureTracker {

    private var ema: Double = 0.5
    private var samples: Int = 0
    /// Weight on the previous mean (higher = smoother, slower to react).
    private let smoothing: Double = 0.85
    private let ciContext: CIContext

    public init(ciContext: CIContext = CIContext(options: [.useSoftwareRenderer: false])) {
        self.ciContext = ciContext
    }

    /// Feeds one photo; returns the gain to apply when accumulating it.
    public func gain(for imageURL: URL) -> Float {
        let mean = meanLuminance(imageURL)
        if samples == 0 {
            ema = mean
        } else {
            ema = smoothing * ema + (1 - smoothing) * mean
        }
        samples += 1
        let target = max(ema, 1e-3)
        let m = max(mean, 1e-3)
        return Float(max(0.6, min(1.8, target / m)))
    }

    /// Reset for a fresh capture session.
    public func reset() { ema = 0.5; samples = 0 }

    private func meanLuminance(_ url: URL) -> Double {
        guard let image = CIImage(contentsOf: url) else { return 0.5 }
        let filter = CIFilter.areaAverage()
        filter.inputImage = image
        filter.extent = image.extent
        guard let output = filter.outputImage,
              let bmp = ciContext.createCGImage(output, from: CGRect(x: 0, y: 0, width: 1, height: 1)),
              let data = bmp.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return 0.5 }
        let r = Double(ptr[0]) / 255.0
        let g = Double(ptr[1]) / 255.0
        let b = Double(ptr[2]) / 255.0
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}
