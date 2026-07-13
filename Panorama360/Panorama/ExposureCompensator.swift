import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers

/// Computes per-photo brightness gains so neighbouring photos blend without
/// visible exposure seams. Uses the mean luminance of each photo (via a GPU
/// area-average) and normalises toward the session-wide mean.
public enum ExposureCompensator {

    /// Returns a gain (≈1.0) per sample, clamped to a safe range.
    public static func gains(for samples: [CaptureSample],
                             loader: (URL) -> CIImage?,
                             context: CIContext) -> [Float] {
        guard !samples.isEmpty else { return [] }

        var means: [Float] = []
        means.reserveCapacity(samples.count)
        for sample in samples {
            guard let image = loader(sample.imageURL) else {
                means.append(0.5)
                continue
            }
            means.append(meanLuminance(image, context: context))
        }

        let total = means.reduce(Double(0)) { $0 + Double($1) }
        let target = max(total / Double(means.count), 1e-3)
        return means.map { raw in
            let m = max(Double(raw), 1e-3)
            let gain = target / m
            return Float(max(0.6, min(1.8, gain)))
        }
    }

    /// Mean luminance in [0,1] by rendering a 1×1 area-average.
    private static func meanLuminance(_ image: CIImage, context: CIContext) -> Float {
        let filter = CIFilter.areaAverage()
        filter.inputImage = image
        filter.extent = image.extent
        guard let output = filter.outputImage else { return 0.5 }

        var pixel: [UInt8] = [0, 0, 0, 0]
        let bitmap = context.createCGImage(output, from: CGRect(x: 0, y: 0, width: 1, height: 1))
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let bmp = bitmap,
              let data = bmp.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return 0.5 }
        _ = cs
        let r = Float(ptr[0]) / 255.0
        let g = Float(ptr[1]) / 255.0
        let b = Float(ptr[2]) / 255.0
        _ = pixel
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}
