import AVFoundation

/// One-shot delegate bridging `AVCapturePhotoCaptureDelegate` callbacks to async.
final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {

    private let continuation: CheckedContinuation<AVCapturePhoto, Error>
    private var hasResolved = false

    init(continuation: CheckedContinuation<AVCapturePhoto, Error>) {
        self.continuation = continuation
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard !hasResolved else { return }
        hasResolved = true
        if let error {
            Log.camera.error("Photo capture failed: \(error.localizedDescription, privacy: .public)")
            continuation.resume(throwing: error)
        } else {
            continuation.resume(returning: photo)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     willBeginCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        Log.camera.debug("Capture begin: \(resolvedSettings.photoWidth)×\(resolvedSettings.photoHeight)")
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        // Shutter closed — photo is being processed.
    }
}
