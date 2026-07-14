import Foundation
import AVFoundation
import ImageIO
import CoreGraphics

/// Serialises photo capture + on-disk persistence so the gate can never
/// double-fire. One capture in flight at a time.
///
/// **Memory model.** Each capture is encoded to JPEG @0.85 and written on a
/// dedicated low-priority background queue, inside an `autoreleasepool`, so the
/// decoded buffer (a full-res frame, ~tens of MB) is freed the instant the file
/// lands — never retained across captures. This is what keeps the scanner under
/// the iOS memory ceiling (the prior SIGKILL/OOM path).
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

    /// Low-priority persistence queue — keeps encoding/writing off the capture
    /// path and the main thread.
    private static let persistQueue = DispatchQueue(label: "com.teleport.capture.persist",
                                                     qos: .utility)

    public init(camera: CameraEngine, store: SessionStore) {
        self.camera = camera
        self.store = store
    }

    /// Captures a photo for `point` and persists it, returning the recorded sample.
    public func capture(point: CapturePoint,
                        orientation: DeviceOrientation,
                        sessionID: UUID) async throws -> CaptureSample {
        guard !inFlight else { throw CaptureError.busy }
        inFlight = true
        defer { inFlight = false }

        let photo = try await camera.capturePhoto()
        let imagesDir = store.imagesDirectory(for: sessionID)

        let (url, width, height): (URL, Int, Int)
        do {
            (url, width, height) = try await Self.persist(photo: photo,
                                                           to: imagesDir,
                                                           name: point.id.uuidString)
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
            exifOrientation: 1, // photos are stored upright (portrait) — see CameraEngine
            timestamp: Date().timeIntervalSince1970
        )
    }

    /// Validates the directory, encodes JPEG @0.85 and writes it — all on the
    /// low-priority queue, inside an `autoreleasepool`. The AVCapturePhoto's
    /// decoded buffer is freed before this returns.
    private static func persist(photo: AVCapturePhoto,
                                to dir: URL,
                                name: String) async throws -> (URL, Int, Int) {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(URL, Int, Int), Error>) in
            persistQueue.async {
                let result: Result<(URL, Int, Int), Error>
                do {
                    let tuple = try autoreleasepool {
                        try ImageWriter.ensureDirectory(dir)
                        return try ImageWriter.writeJPEG(from: photo, to: dir, name: name)
                    }
                    result = .success((tuple.url, tuple.width, tuple.height))
                } catch {
                    result = .failure(error)
                }
                cont.resume(with: result)
            }
        }
    }
}
