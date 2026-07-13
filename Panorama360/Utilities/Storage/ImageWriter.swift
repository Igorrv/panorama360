import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import CoreImage

/// Writes captured photos and rendered panoramas to disk (HEIC by default).
public enum ImageWriter {

    /// Writes an `AVCapturePhoto` (already encoded by AVFoundation) to disk.
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

    /// Renders and writes a `CGImage` to `url`. Format inferred from the path extension.
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

    // MARK: - Helpers

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
        case .noData: return "AVCapturePhoto produced no data."
        case .destinationFailed: return "Could not create image destination."
        case .finalizeFailed: return "Could not finalise image write."
        case .renderFailed: return "Could not render CIImage to CGImage."
        }
    }
}
