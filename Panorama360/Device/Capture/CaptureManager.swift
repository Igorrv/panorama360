import Foundation
import AVFoundation
import ImageIO
import CoreGraphics
import UIKit

/// Serialises photo capture behind a **dual-stream** pipeline so the scanner
/// never retains a full-resolution buffer in RAM (the prior OOM/SIGKILL path).
///
/// - **Stream A (low-latency UI):** the instant photo data is intercepted, a
///   256×256 thumbnail is extracted from the in-memory bytes — a down-scaled
///   decode (`CGImageSourceCreateThumbnailAtIndex`), never the full frame — and
///   published on the main thread via `setThumbnailHandler`, so the live 3D
///   node is textured at once.
/// - **Stream B (high-res persistence):** the full frame is decoded **once**,
///   recompressed to JPEG @0.85 and written into `NSTemporaryDirectory()` on a
///   low-priority queue inside an `autoreleasepool`, so the heavy buffer is
///   freed the instant the file lands.
public actor CaptureManager {

    public enum CaptureError: LocalizedError {
        case busy
        case noPhotoOutput
        case cameraNoData
        case writeFailed(String)
        public var errorDescription: String? {
            switch self {
            case .busy:                 return "Uma captura já está em andamento."
            case .noPhotoOutput:        return "A câmera não está pronta."
            case .cameraNoData:         return "A câmera não retornou dados — tente novamente."
            case .writeFailed(let d):   return "Não foi possível salvar a foto: \(d)"
            }
        }
    }

    private let camera: CameraEngine
    private let store: SessionStore
    private var inFlight = false

    /// Stream A receiver: `(nodeUUID, 256 thumbnail)`. Installed once at session
    /// start via the actor-isolated `setThumbnailHandler`.
    private var thumbnailHandler: ((UUID, UIImage) -> Void)?

    /// Low-priority persistence queue — keeps both streams off the capture path
    /// and the main thread.
    private static let persistQueue = DispatchQueue(label: "com.teleport.capture.persist",
                                                     qos: .utility)

    public init(camera: CameraEngine, store: SessionStore) {
        self.camera = camera
        self.store = store
    }

    /// Installs the Stream A receiver. Actor-isolated, so call it from an async
    /// context (the view-model's `start()`).
    public func setThumbnailHandler(_ handler: ((UUID, UIImage) -> Void)?) {
        thumbnailHandler = handler
    }

    /// Captures `point`, fanning the photo into the dual stream. The thumbnail
    /// has already left via the handler by the time this returns.
    public func capture(point: CapturePoint,
                        orientation: DeviceOrientation,
                        sessionID: UUID) async throws -> CaptureSample {
        guard !inFlight else { throw CaptureError.busy }
        inFlight = true
        defer { inFlight = false }

        let photo = try await camera.capturePhoto()
        let streamA = thumbnailHandler

        let (url, width, height): (URL, Int, Int)
        do {
            (url, width, height) = try await Self.process(photo: photo,
                                                          nodeID: point.id,
                                                          sessionID: sessionID,
                                                          streamA: streamA)
        } catch ImageWriterError.noData {
            throw CaptureError.cameraNoData
        } catch {
            Log.capture.error("Write failed: \(error.localizedDescription, privacy: .public)")
            throw CaptureError.writeFailed(error.localizedDescription)
        }

        let intrinsics = camera.intrinsics(forPhotoWidth: width, height: height)
        return CaptureSample(
            imageURL: url,
            width: width,
            height: height,
            intrinsics: intrinsics,
            quaternion: orientation.quaternion,
            pitch: orientation.pitch,
            yaw: orientation.yaw,
            exifOrientation: 1, // stored upright (portrait) — see CameraEngine
            timestamp: Date().timeIntervalSince1970
        )
    }

    /// Runs both streams on the low-priority queue inside one `autoreleasepool`.
    private static func process(photo: AVCapturePhoto,
                                nodeID: UUID,
                                sessionID: UUID,
                                streamA: ((UUID, UIImage) -> Void)?) async throws -> (URL, Int, Int) {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(URL, Int, Int), Error>) in
            persistQueue.async {
                let outcome: Result<(URL, Int, Int), Error>
                do {
                    let tuple = try autoreleasepool {
                        try dualStream(photo: photo, nodeID: nodeID, sessionID: sessionID, streamA: streamA)
                    }
                    outcome = .success(tuple)
                } catch {
                    outcome = .failure(error)
                }
                cont.resume(with: outcome)
            }
        }
    }

    /// Stream A (thumbnail) + Stream B (JPEG archive), sharing one data blob.
    private static func dualStream(photo: AVCapturePhoto,
                                   nodeID: UUID,
                                   sessionID: UUID,
                                   streamA: ((UUID, UIImage) -> Void)?) throws -> (URL, Int, Int) {
        guard let data = photo.fileDataRepresentation() else { throw ImageWriterError.noData }

        // Stream A: ultra-light thumbnail from the in-memory data (down-scaled).
        if let thumb = thumbnail256(from: data) {
            DispatchQueue.main.async { streamA?(nodeID, thumb) }
        }

        // Stream B: full-res JPEG @0.85 into NSTemporaryDirectory().
        let dir = archiveDirectory(sessionID: sessionID)
        try ImageWriter.ensureDirectory(dir)
        let jpgURL = dir.appendingPathComponent(nodeID.uuidString).appendingPathExtension("jpg")

        if let cg = decode(data) {
            try ImageWriter.write(cg, to: jpgURL, compressionQuality: 0.85)
            Log.storage.info("Archived JPEG \(jpgURL.lastPathComponent, privacy: .public) (\(cg.width)×\(cg.height))")
            return (jpgURL, cg.width, cg.height)
        }
        // Fallback: the camera's original payload, untouched.
        let dims = metadataDimensions(from: data) ?? (4032, 3024)
        try data.write(to: jpgURL, options: .atomic)
        Log.storage.info("Archived raw \(jpgURL.lastPathComponent, privacy: .public) (fallback)")
        return (jpgURL, dims.0, dims.1)
    }

    // MARK: - Helpers

    private static func archiveDirectory(sessionID: UUID) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("panorama360", isDirectory: true)
            .appendingPathComponent(sessionID.uuidString, isDirectory: true)
    }

    /// Exactly 256×256 (aspect-fill crop) via a down-scaled thumbnail decode —
    /// never decodes the full-resolution frame.
    private static func thumbnail256(from data: Data) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 256,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return squareFill(cg, side: 256)
    }

    /// Aspect-fill a CGImage into a `side`×`side` UIImage (upright, centred).
    private static func squareFill(_ cg: CGImage, side: Int) -> UIImage? {
        let s = CGFloat(side)
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let scale = max(s / w, s / h)
        let drawW = w * scale, drawH = h * scale
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
            UIImage(cgImage: cg, scale: 1, orientation: .up)
                .draw(in: CGRect(x: (s - drawW) / 2, y: (s - drawH) / 2,
                                 width: drawW, height: drawH))
        }
    }

    private static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Pixel dimensions from metadata — **no pixel decode**.
    private static func metadataDimensions(from data: Data) -> (Int, Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (w, h)
    }
}
