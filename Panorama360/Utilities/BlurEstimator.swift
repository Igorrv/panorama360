import Accelerate

/// Estimates frame sharpness via the variance of the Laplacian on the luma plane.
///
/// Higher score = sharper image. Operates on a centre region-of-interest and in
/// single-precision for speed so it can run every frame during the capture gate.
public enum BlurEstimator {

    /// Laplacian 3×3 kernel (ish): emphasises high frequencies.
    private static let laplacianKernel: [Float] = [
         0,  1,  0,
         1, -4,  1,
         0,  1,  0
    ]

    /// Returns a sharpness score for a YUV bi-planar pixel buffer (e.g. an ARFrame's
    /// `capturedImage`). Returns `0` if the buffer is not suitable.
    public static func sharpnessScore(of pixelBuffer: CVPixelBuffer?) -> Float {
        guard let pb = pixelBuffer else { return 0 }
        guard CVPixelBufferGetPixelFormatType(pb) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                || CVPixelBufferGetPixelFormatType(pb) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange else {
            return 0
        }
        guard CVPixelBufferGetPlaneCount(pb) >= 1 else { return 0 }

        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }

        let planeW = Int(CVPixelBufferGetWidthOfPlane(pb, 0))
        let planeH = Int(CVPixelBufferGetHeightOfPlane(pb, 0))
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pb, 0) else { return 0 }

        // Centre ROI (≤ 320px) for constant, low cost.
        let roi = 320
        let w = min(roi, planeW) & ~1
        let h = min(roi, planeH) & ~1
        guard w >= 16, h >= 16 else { return 0 }
        let offX = (planeW - w) / 2
        let offY = (planeH - h) / 2

        var src = vImage_Buffer(data: base,
                                height: vImagePixelCount(h),
                                width: vImagePixelCount(w),
                                rowBytes: rowBytes)
        // Advance to ROI start.
        src.data = base.advanced(by: offY * rowBytes + offX)

        return laplacianVariance(src: src, width: w, height: h, rowBytes: rowBytes)
    }

    // MARK: - Internals

    private static func laplacianVariance(src: vImage_Buffer,
                                          width: Int, height: Int, rowBytes: Int) -> Float {
        var floatBuffer = [Float](repeating: 0, count: width * height)
        var convBuffer  = [Float](repeating: 0, count: width * height)

        var dst = vImage_Buffer(data: &floatBuffer,
                                height: vImagePixelCount(height),
                                width: vImagePixelCount(width),
                                rowBytes: width * MemoryLayout<Float>.size)

        // Planar8 → PlanarF (0..255).
        var maxFloat: Float = 255
        var minFloat: Float = 0
        vImageConvert_Planar8toPlanarF(&src, &dst, maxFloat, minFloat, vImage_Flags(kvImageNoFlags))

        var conv = vImage_Buffer(data: &convBuffer,
                                 height: vImagePixelCount(height),
                                 width: vImagePixelCount(width),
                                 rowBytes: width * MemoryLayout<Float>.size)

        let err = vImageConvolve_PlanarF(&dst, &conv, nil, 0, 0,
                                         UInt32(width), UInt32(height),
                                         laplacianKernel, 3, 3, 0, nil,
                                         vImage_Flags(kvImageEdgeExtend))
        guard err == kvImageNoError else { return 0 }

        // Variance of the Laplacian response.
        var mean: Float = 0
        var stdDev: Float = 0
        vImageVariance_PlanarF(&conv, &mean, &stdDev, vImage_Flags(kvImageNoFlags))
        // Variance = stdDev^2 (vImageVariance returns mean & stddev).
        return stdDev * stdDev
    }
}
