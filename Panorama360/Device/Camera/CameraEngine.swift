import AVFoundation
import UIKit
import CoreImage

/// Owns the rear-camera `AVCaptureSession`: live preview, full-resolution HDR
/// HEIC still capture, and a video stream for sharpness estimation.
///
/// **Why AVCaptureSession (and not ARKit) owns the camera:** iOS grants the
/// camera exclusively. AVCaptureSession gives us HDR stills in HEIC at full
/// resolution (the spec's quality requirement); ARKit would lock us to its
/// lower-res video frames. Orientation therefore comes from CoreMotion, not
/// ARKit — see `MotionEngine`. `ARSessionManager` is provided for the alternate
/// ARKit-owned-camera path.
public final class CameraEngine: NSObject {

    public enum CameraError: LocalizedError {
        case unauthorized
        case noRearCamera
        case configurationFailed(String)
        case runtimeError(String)
        public var errorDescription: String? {
            switch self {
            case .unauthorized: return "Camera permission not granted."
            case .noRearCamera: return "No rear camera available on this device."
            case .configurationFailed(let detail): return "Failed to configure the camera session: \(detail)"
            case .runtimeError(let detail): return "Camera runtime error: \(detail)"
            }
        }
    }

    public let session = AVCaptureSession()
    public let previewLayer: AVCaptureVideoPreviewLayer

    private let sessionQueue = DispatchQueue(label: "com.teleport.camera.session")
    /// Retained for the lifetime of the engine. AVCaptureVideoDataOutput does NOT
    /// retain the delegate queue, so it must be stored as a property. (A previous
    /// inline queue was released as soon as `configure()` returned, then the first
    /// delivered frame dispatched into freed memory → crash ~2–3s after start.)
    private let videoQueue = DispatchQueue(label: "com.teleport.camera.video")
    private var photoOutput: AVCapturePhotoOutput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private(set) var videoDevice: AVCaptureDevice?
    private var sampleProxy = SampleBufferProxy()
    private var configured = false

    /// Latest sharpness score computed from the video stream (updated ~camera fps).
    public var onSharpness: ((Float) -> Void)?
    /// Fired when the session reports a runtime error (hardware reset, etc.).
    public var onRuntimeError: ((String) -> Void)?
    public private(set) var lastRuntimeError: String?
    /// Latest captured image buffer (for the live-preview/blur gate).
    public private(set) var latestPixelBuffer: CVPixelBuffer?

    public override init() {
        previewLayer = AVCaptureVideoPreviewLayer()
        super.init()
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        sampleProxy.handler = { [weak self] buffer in
            self?.handleSampleBuffer(buffer)
        }
        // Surface session failures (e.g. media services reset) instead of dying.
        NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionRuntimeError,
            object: session, queue: .main) { [weak self] note in
            let detail = (note.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription
                ?? "Unknown capture session error."
            self?.lastRuntimeError = detail
            self?.onRuntimeError?(detail)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        let session = self.session
        sessionQueue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    // MARK: - Authorization

    public func requestAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    // MARK: - Lifecycle

    /// Configures (once) and starts the session. Throws on configuration or
    /// runtime failure so the caller can surface it to the UI instead of leaving
    /// a dead black screen.
    public func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CameraError.configurationFailed("engine released"))
                    return
                }
                do {
                    if !self.configured { try self.configure(); self.configured = true }
                    if !self.session.isRunning { self.session.startRunning() }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func stop() {
        sessionQueue.async { [weak self] in
            guard self?.session.isRunning == true else { return }
            self?.session.stopRunning()
        }
    }

    // MARK: - Configuration

    private func configure() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // Clean any prior wiring (safe if configure is ever re-run).
        for input in session.inputs { session.removeInput(input) }
        for output in session.outputs { session.removeOutput(output) }

        // Prefer the ultra-wide (0.5x, "grande angular", ~120° FOV) so each shot
        // covers far more of the sphere and every guide point is reachable while
        // rotating in place. Fall back to the standard wide-angle on devices
        // without an ultra-wide lens.
        let device: AVCaptureDevice
        if let ultra = AVCaptureDevice.default(.builtInUltraWideCamera,
                                                for: .video, position: .back) {
            device = ultra
        } else if let wide = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                      for: .video, position: .back) {
            device = wide
        } else {
            throw CameraError.noRearCamera
        }
        videoDevice = device

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw CameraError.configurationFailed("device input: \(error.localizedDescription)")
        }
        guard session.canAddInput(input) else {
            throw CameraError.configurationFailed("cannot add camera input")
        }
        session.addInput(input)

        // Photo output (HDR HEIC).
        let photoOutput = AVCapturePhotoOutput()
        guard session.canAddOutput(photoOutput) else {
            throw CameraError.configurationFailed("cannot add photo output")
        }
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality
        // Store photos upright (portrait) so the stitcher loads raw pixels with
        // no EXIF-rotation handling.
        if let connection = photoOutput.connection(with: .video) {
            if #available(iOS 17.0, *) {
                connection.videoRotationAngle = 90 // portrait
            } else {
                connection.videoOrientation = .portrait
            }
        }
        self.photoOutput = photoOutput

        // Video output for sharpness sampling.
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        guard session.canAddOutput(videoOutput) else {
            throw CameraError.configurationFailed("cannot add video output")
        }
        session.addOutput(videoOutput)
        videoOutput.setSampleBufferDelegate(sampleProxy, queue: videoQueue)
        self.videoOutput = videoOutput

        configureDeviceControls(device)
    }

    private func configureDeviceControls(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            device.unlockForConfiguration()
        } catch {
            Log.camera.error("Device config error: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Capture

    /// Captures a single full-resolution HDR HEIC photo.
    ///
    /// A 6 s timeout guarantees the continuation resumes even if AVFoundation
    /// never calls back (interrupted capture / session reset / backgrounding) —
    /// otherwise the delegate would deinit with an unresumed `CheckedContinuation`
    /// and trap. The delegate tolerates the late callback via `hasResolved`.
    public func capturePhoto() async throws -> AVCapturePhoto {
        guard let photoOutput else { throw CameraError.configurationFailed("photo output not ready") }
        let settings = makePhotoSettings(output: photoOutput)
        return try await withCheckedThrowingContinuation { continuation in
            // The photo output retains the delegate for the duration of the capture.
            let delegate = PhotoCaptureDelegate(continuation: continuation)
            photoOutput.capturePhoto(with: settings, delegate: delegate)
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 6.0) {
                delegate.timeoutResume()
            }
        }
    }

    private func makePhotoSettings(output: AVCapturePhotoOutput) -> AVCapturePhotoSettings {
        let settings: AVCapturePhotoSettings
        if output.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        } else {
            settings = AVCapturePhotoSettings()
        }
        settings.flashMode = .off
        settings.photoQualityPrioritization = .quality
        return settings
    }

    // MARK: - Status & intrinsics

    public var currentStatus: CameraStatus {
        CameraStatus.current(from: videoDevice)
    }

    /// Approximate pinhole intrinsics for the captured photo, derived from the
    /// device's horizontal field of view. Square pixels and a centred principal
    /// point are assumed — adequate for the projection-based stitcher.
    public func intrinsics(forPhotoWidth width: Int, height: Int) -> CameraIntrinsics {
        guard let device = videoDevice,
              let format = device.activeFormat as AVCaptureDevice.Format? else {
            return CameraIntrinsics(fx: Float(width), fy: Float(width),
                                    cx: Float(width) / 2, cy: Float(height) / 2)
        }
        let hfov = Double(format.videoFieldOfView) * .pi / 180
        let fx = Float((Double(width) / 2) / tan(hfov / 2))
        // Ultra-wide (~120°) carries strong barrel distortion; plain wide / any
        // unknown lens → identity (no change). Gated by LensProfileTable.
        let isUltraWide = device.deviceType == .builtInUltraWideCamera
        let profile = LensProfileTable.profile(isUltraWide: isUltraWide)
        return CameraIntrinsics(fx: fx, fy: fx,
                                cx: Float(width) / 2, cy: Float(height) / 2,
                                k1: profile.k1, k2: profile.k2, k3: profile.k3)
    }

    // MARK: - Sample buffer handling

    private func handleSampleBuffer(_ buffer: CVPixelBuffer) {
        latestPixelBuffer = buffer
        let score = BlurEstimator.sharpnessScore(of: buffer)
        onSharpness?(score)
    }
}

/// Forwards video sample buffers off the capture queue.
private final class SampleBufferProxy: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var handler: ((CVPixelBuffer) -> Void)?

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        handler?(buffer)
    }
}
