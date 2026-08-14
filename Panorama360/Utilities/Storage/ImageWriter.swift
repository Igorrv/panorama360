import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import CoreImage

/// Writes captured photos and rendered panoramas to disk.
///
/// Capture path (`writeJPEG`) decodes the `AVCapturePhoto` **once** and
/// recompresses to JPEG @0.85, so the heavy buffer is freed the instant the
/// file lands (call it inside an `autoreleasepool` on a background queue). It
/// never holds raw pixels across captures — that was the OOM path.
public enum ImageWriter {

    // MARK: - Directory safety

    /// Validates/creates a directory. Idempotent; safe to call before every write.
    public static func ensureDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    // MARK: - Capture: AVCapturePhoto → JPEG @ quality

    /// Encodes an `AVCapturePhoto` to JPEG at `quality` and writes it to
    /// `dir/<name>.jpg`, returning the URL + pixel dimensions. Decodes exactly
    /// once (so width/height come for free — no separate decode pass).
    ///
    /// If decode or recompress fails, it falls back to writing the camera's
    /// original bytes as-is, so a capture is never silently lost to a transcode
    /// hiccup. Dimensions then come from metadata (no decode).
    public static func writeJPEG(from photo: AVCapturePhoto,
                                 to dir: URL,
                                 name: String,
                                 quality: CGFloat = 0.85) throws -> (url: URL, width: Int, height: Int) {
        guard let data = photo.fileDataRepresentation() else {
            throw ImageWriterError.noData
        }
        let jpgURL = dir.appendingPathComponent(name).appendingPathExtension("jpg")

        // Preferred path: decode once → rotate upright → recompress JPEG @ quality.
        if let decoded = Self.decode(data) {
            let cg = Self.upright(decoded, orientation: Self.orientation(of: photo))
            do {
                try write(cg, to: jpgURL, compressionQuality: quality)
                Log.storage.info("Saved JPEG \(jpgURL.lastPathComponent, privacy: .public) (\(cg.width)×\(cg.height))")
                return (jpgURL, cg.width, cg.height)
            } catch {
                Log.storage.warning("JPEG recompress failed, writing raw bytes: \(error.localizedDescription, privacy: .public)")
            }
        }

        // Fallback: the camera's original payload, untouched. The stitcher reads
        // raw pixels, so a non-upright photo here will be rotated in the sphere.
        let ext = preferredExtension(for: data) ?? "jpg"
        let rawURL = dir.appendingPathComponent(name).appendingPathExtension(ext)
        try data.write(to: rawURL, options: .atomic)
        let dims = dimensions(from: data) ?? (4032, 3024)
        Log.storage.warning("Saved raw \(rawURL.lastPathComponent, privacy: .public) (fallback — orientation not normalised)")
        return (rawURL, dims.0, dims.1)
    }

    /// Backwards-compatible HEIC writer (renders + writer pipeline still uses it).
    public static func write(photo: AVCapturePhoto,
                             to directory: URL,
                             name: String = UUID().uuidString) throws -> URL {
        guard let data = photo.fileDataRepresentation() else {
            throw ImageWriterError.noData
        }
        let ext = preferredExtension(for: data) ?? "heic"
        let url = directory.appendingPathComponent(name).appendingPathExtension(ext)
        try data.write(to: url, options: .atomic)
        Log.storage.info("Saved photo \(url.lastPathComponent, privacy: .public) (\(data.count) bytes)")
        return url
    }

    /// Renders and writes a `CGImage` to `url`. Format inferred from the extension.
    public static func write(_ image: CGImage, to url: URL, compressionQuality: CGFloat = 0.92) throws {
        let utType: CFString
        switch url.pathExtension.lowercased() {
        case "png":  utType = UTType.png.identifier as CFString
        case "jpg", "jpeg": utType = UTType.jpeg.identifier as CFString
        default: utType = UTType.heic.identifier as CFString
        }

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, utType, 1, nil) else {
            throw ImageWriterError.destinationFailed
        }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: compressionQuality
        ]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageWriterError.finalizeFailed }
    }

    /// Renders and writes a `CIImage` to `url` via the given context.
    public static func write(_ image: CIImage,
                             to url: URL,
                             context: CIContext,
                             compressionQuality: CGFloat = 0.92) throws {
        let cgImage = context.createCGImage(image, from: image.extent)
        guard let cg = cgImage else { throw ImageWriterError.renderFailed }
        try write(cg, to: url, compressionQuality: compressionQuality)
    }

    // MARK: - Orientation

    /// The orientation AVFoundation attached to the capture.
    public static func orientation(of photo: AVCapturePhoto) -> CGImagePropertyOrientation {
        guard let raw = photo.metadata[kCGImagePropertyOrientation as String] as? NSNumber,
              let orientation = CGImagePropertyOrientation(rawValue: raw.uint32Value) else {
            return .up
        }
        return orientation
    }

    /// Rotates the pixels so the stored file needs no orientation metadata.
    ///
    /// Setting the capture connection to portrait does not guarantee rotated
    /// pixels — AVFoundation is free to leave them in sensor orientation and
    /// describe the rotation in EXIF instead. The stitcher reads raw pixels and
    /// ignores EXIF, so a photo left that way lands in the sphere rotated 90°.
    /// Baking the rotation in here makes the on-disk file the single truth, and
    /// costs nothing extra because this path already decodes and re-encodes.
    public static func upright(_ image: CGImage,
                               orientation: CGImagePropertyOrientation) -> CGImage {
        guard orientation != .up else { return image }
        let oriented = CIImage(cgImage: image).oriented(orientation)
        guard let rotated = sharedContext.createCGImage(oriented, from: oriented.extent) else {
            Log.storage.warning("Could not rotate photo upright; storing as captured")
            return image
        }
        return rotated
    }

    /// Reused across captures — building a `CIContext` per photo is expensive.
    private static let sharedContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Helpers

    /// One-shot decode of image bytes to a `CGImage`.
    private static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Pixel dimensions from metadata — **no pixel decode**.
    private static func dimensions(from data: Data) -> (Int, Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (w, h)
    }

    private static func preferredExtension(for data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let utType = CGImageSourceGetType(source) else { return nil }
        return (utType as String).contains("heic") ? "heic" : "jpg"
    }
}

public enum ImageWriterError: LocalizedError {
    case noData
    case destinationFailed
    case finalizeFailed
    case renderFailed

    public var errorDescription: String? {
        switch self {
        case .noData: return "A câmera não retornou dados de imagem."
        case .destinationFailed: return "Could not create image destination."
        case .finalizeFailed: return "Could not finalise image write."
        case .renderFailed: return "Could not render CIImage to CGImage."
        }
    }
}
