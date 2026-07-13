import Foundation
import AVFoundation

/// Serialises photo capture + on-disk persistence so the gate can never
/// double-fire. One capture in flight at a time.
public actor CaptureManager {

    public enum CaptureError: LocalizedError {
        case busy
        case noPhotoOutput
        case writeFailed
        public var errorDescription: String? {
            switch self {
            case .busy: return "A capture is already in progress."
            case .noPhotoOutput: return "Camera not ready."
            case .writeFailed: return "Failed to save the photo."
            }
        }
    }

    private let camera: CameraEngine
    private let store: SessionStore
    private var inFlight = false

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
        let url: URL
        do {
            url = try ImageWriter.write(photo: photo, to: imagesDir, name: point.id.uuidString)
        } catch {
            Log.capture.error("Write failed: \(error.localizedDescription, privacy: .public)")
            throw CaptureError.writeFailed
        }

        let width = Int(photo.pixelWidth)
        let height = Int(photo.pixelHeight)
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
}
