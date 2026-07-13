import AVFoundation

/// One-shot delegate bridging `AVCapturePhotoCaptureDelegate` callbacks to async.
///
/// **Hardening.** A `CheckedContinuation` traps if it is ever resumed twice OR
/// never resumed (it asserts on deinit). Two real failure modes:
/// 1. AVFoundation delivers `didFinishProcessingPhoto` more than once for one
///    request (rare, but possible with some capture-path resets).
/// 2. The callback **never** fires — e.g. the capture is interrupted by the app
///    backgrounding, a session reset, or a runtime error mid-capture. The
///    delegate would then be released with the continuation unresumed → trap →
///    crash. This is the prime suspect for the sideload crash after the camera
///    opens: a capture fires, gets interrupted, and the app dies.
///
/// Both are eliminated by: (a) funnelling every resume path through `complete`
/// guarded by `hasResolved` + a lock, and (b) `timeoutResume()` — scheduled by
/// the engine — which guarantees the continuation resumes exactly once even if
/// AVFoundation stays silent.
final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {

    private var continuation: CheckedContinuation<AVCapturePhoto, Error>?
    private var hasResolved = false
    private let lock = NSLock()

    /// Error surfaced when AVFoundation never calls back within the timeout.
    enum TimeoutError: Error, LocalizedError {
        case photoCaptureTimedOut
        var errorDescription: String? {
            "The camera did not return a photo in time (capture interrupted)."
        }
    }

    init(continuation: CheckedContinuation<AVCapturePhoto, Error>) {
        self.continuation = continuation
    }

    /// Resolves the continuation exactly once, from any thread.
    private func complete(with result: Result<AVCapturePhoto, Error>) {
        lock.lock()
        guard !hasResolved, let cont = continuation else {
            lock.unlock(); return
        }
        hasResolved = true
        continuation = nil   // release the continuation; further calls no-op
        lock.unlock()
        switch result {
        case .success(let photo): cont.resume(returning: photo)
        case .failure(let error): cont.resume(throwing: error)
        }
    }

    /// Safety valve invoked by `CameraEngine` after a deadline. If AVFoundation
    /// has already delivered (or already failed), this is a no-op.
    func timeoutResume() {
        complete(with: .failure(TimeoutError.photoCaptureTimedOut))
    }

    // MARK: - AVCapturePhotoCaptureDelegate

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error {
            Log.camera.error("Photo capture failed: \(error.localizedDescription, privacy: .public)")
            complete(with: .failure(error))
        } else {
            complete(with: .success(photo))
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     willBeginCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        Log.camera.debug("Capture begin for uniqueID \(resolvedSettings.uniqueID)")
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        // Shutter closed — photo is being processed.
    }
}
