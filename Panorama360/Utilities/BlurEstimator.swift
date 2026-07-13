import Accelerate
import CoreVideo

/// Estimates frame sharpness via the variance of the Laplacian on the luma plane.
///
/// Higher score = sharper image. Operates on a centre region-of-interest and in
/// single-precision for speed so it can run every frame during the capture gate.
public enum BlurEstimator {

    /// Laplacian 3×3 kernel: emphasises high frequencies.
    private static let laplacianKernel: [Float] = [
         0,  1,  0,
         1, -4,  1,
         0,  1,  0
    ]

    /// Returns a sharpness score for a YUV bi-planar pixel buffer (e.g. an ARFrame's
    /// `capturedImage`). Returns `0` if the buffer is not suitable.
    public static func sharpnessScore(of pixelBuffer: CVPixelBuffer?) -> Float {
        guard let pb = pixelBuffer else { return 0 }
        let format = CVPixelBufferGetPixelFormatType(pb)
        guard format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange else {
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

        var src = vImage_Buffer(
            data: base.advanced(by: offY * rowBytes + offX),
            height: vImagePixelCount(h),
            width: vImagePixelCount(w),
            rowBytes: rowBytes
        )
        return laplacianVariance(src: &src, width: w, height: h)
    }

    // MARK: - Internals

    private static func laplacianVariance(src: inout vImage_Buffer,
                                          width: Int, height: Int) -> Float {
        var floatBuffer = [Float](repeating: 0, count: width * height)
        var convBuffer = [Float](repeating: 0, count: width * height)

        let floatRowBytes = width * MemoryLayout<Float>.size
        let count = vDSP_Length(width * height)

        return floatBuffer.withUnsafeMutableBytes { floatRaw in
            convBuffer.withUnsafeMutableBytes { convRaw in
                var dst = vImage_Buffer(
                    data: floatRaw.baseAddress,
                    height: vImagePixelCount(height),
                    width: vImagePixelCount(width),
                    rowBytes: floatRowBytes
                )
                var conv = vImage_Buffer(
                    data: convRaw.baseAddress,
                    height: vImagePixelCount(height),
                    width: vImagePixelCount(width),
                    rowBytes: floatRowBytes
                )

                let maxFloat: Float = 255
                let minFloat: Float = 0
                vImageConvert_Planar8toPlanarF(&src, &dst, maxFloat, minFloat, vImage_Flags(kvImageNoFlags))

                let err = laplacianKernel.withUnsafeBufferPointer { kernelPtr in
                    vImageConvolve_PlanarF(
                        &dst, &conv, nil, 0, 0,
                        kernelPtr.baseAddress!, 3, 3,
                        0,
                        vImage_Flags(kvImageEdgeExtend)
                    )
                }
                guard err == kvImageNoError,
                      let convBase = conv.data?.assumingMemoryBound(to: Float.self) else {
                    return Float(0)
                }

                var mean: Float = 0
                var meanSquare: Float = 0
                vDSP_meanv(convBase, 1, &mean, count)
                vDSP_measqv(convBase, 1, &meanSquare, count)
                let variance = meanSquare - mean * mean
                return max(0, variance)
            }
        }
    }
}
