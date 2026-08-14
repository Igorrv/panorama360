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

    /// Sharpness is sampled on a timer rather than every frame: the gate only
    /// reads it at 15 Hz, and a Laplacian over a full preview frame at 30–60 fps
    /// is pure heat. Touched only on `videoQueue`.
    private var lastSharpnessTime: CFTimeInterval = 0
    private static let sharpnessInterval: CFTimeInterval = 1.0 / 12

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
                    // Only valid once the preset has settled on an active format.
                    self.applyMaxPhotoDimensions()
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

        // Stills, not video. Without this the session defaults to `.high`, which
        // activates a 16:9 video format: the photos come back cropped top and
        // bottom (fewer degrees per shot ⇒ holes in the sphere) and below the
        // sensor's full resolution.
        if session.canSetSessionPreset(.photo) { session.sessionPreset = .photo }

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
        settings.maxPhotoDimensions = output.maxPhotoDimensions
        return settings
    }

    /// Raises the photo output to the largest resolution the active format
    /// offers, capped so a 48 MP sensor cannot hand the stitcher buffers it
    /// will be jetsam-killed for. Must run inside a configuration transaction.
    private func applyMaxPhotoDimensions() {
        guard let photoOutput, let device = videoDevice else { return }
        let affordable = device.activeFormat.supportedMaxPhotoDimensions.filter {
            Int($0.width) * Int($0.height) <= Self.maxPhotoPixels
        }
        guard let best = affordable.max(by: {
            Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
        }) else { return }
        session.beginConfiguration()
        photoOutput.maxPhotoDimensions = best
        session.commitConfiguration()
        Log.camera.info("Photo dimensions \(best.width, privacy: .public)×\(best.height, privacy: .public)")
    }

    private static let maxPhotoPixels = 16_000_000

    // MARK: - Status & intrinsics

    public var currentStatus: CameraStatus {
        CameraStatus.current(from: videoDevice)
    }

    /// Field of view of a photo as it is **stored** (upright portrait), radians.
    /// `AVCaptureDevice.Format.videoFieldOfView` describes the sensor's *long*
    /// axis, which portrait rotation turns into the image height — so the two
    /// are not interchangeable and confusing them skews every projection.
    public struct PhotoFOV: Sendable {
        /// Across the image width — what the screen shows left-to-right.
        public let horizontal: Double
        /// Across the image height — equals the sensor's quoted field of view.
        public let vertical: Double
        /// Half of the narrower axis: the radius a single shot really covers.
        public var narrowHalf: Double { min(horizontal, vertical) / 2 }
    }

    /// FOV of the current lens/format, or nil before the session is configured.
    public var photoFOV: PhotoFOV? {
        guard let device = videoDevice else { return nil }
        let format = device.activeFormat
        let sensorFOV = Double(format.videoFieldOfView) * .pi / 180
        guard sensorFOV > 0 else { return nil }
        let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let long = Double(max(dims.width, dims.height))
        let short = Double(min(dims.width, dims.height))
        guard long > 0, short > 0 else { return nil }
        return PhotoFOV(horizontal: 2 * atan(tan(sensorFOV / 2) * (short / long)),
                        vertical: sensorFOV)
    }

    /// Approximate pinhole intrinsics for the captured photo. Square pixels and
    /// a centred principal point are assumed — adequate for the projection-based
    /// stitcher.
    ///
    /// The focal length is derived from the photo's **long side**, because that
    /// is the axis `videoFieldOfView` measures. Deriving it from the portrait
    /// width instead (as this did) left every focal length ~33% short on a 4:3
    /// sensor, so each photo was projected onto far more of the sphere than it
    /// actually covered and neighbouring shots could never line up.
    public func intrinsics(forPhotoWidth width: Int, height: Int) -> CameraIntrinsics {
        let longSide = Double(max(width, height))
        let cx = Float(width) / 2, cy = Float(height) / 2
        guard let device = videoDevice else {
            return CameraIntrinsics(fx: Float(longSide), fy: Float(longSide), cx: cx, cy: cy)
        }
        let sensorFOV = Double(device.activeFormat.videoFieldOfView) * .pi / 180
        guard sensorFOV > 0 else {
            return CameraIntrinsics(fx: Float(longSide), fy: Float(longSide), cx: cx, cy: cy)
        }
        let focal = Float((longSide / 2) / tan(sensorFOV / 2))
        // Ultra-wide (~120°) carries strong barrel distortion; plain wide / any
        // unknown lens → identity (no change). Gated by LensProfileTable.
        let isUltraWide = device.deviceType == .builtInUltraWideCamera
        let profile = LensProfileTable.profile(isUltraWide: isUltraWide)
        return CameraIntrinsics(fx: focal, fy: focal, cx: cx, cy: cy,
                                k1: profile.k1, k2: profile.k2, k3: profile.k3)
    }

    // MARK: - Sample buffer handling

    private func handleSampleBuffer(_ buffer: CVPixelBuffer) {
        let now = CACurrentMediaTime()
        guard now - lastSharpnessTime >= Self.sharpnessInterval else { return }
        lastSharpnessTime = now
        onSharpness?(BlurEstimator.sharpnessScore(of: buffer))
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
