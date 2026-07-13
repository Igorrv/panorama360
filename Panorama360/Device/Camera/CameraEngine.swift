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
        case configurationFailed
        public var errorDescription: String? {
            switch self {
            case .unauthorized: return "Camera permission not granted."
            case .noRearCamera: return "No rear camera available on this device."
            case .configurationFailed: return "Failed to configure the camera session."
            }
        }
    }

    public let session = AVCaptureSession()
    public let previewLayer: AVCaptureVideoPreviewLayer

    private let sessionQueue = DispatchQueue(label: "com.teleport.camera.session")
    private var photoOutput: AVCapturePhotoOutput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private(set) var videoDevice: AVCaptureDevice?
    private var sampleProxy = SampleBufferProxy()

    /// Latest sharpness score computed from the video stream (updated ~camera fps).
    public var onSharpness: ((Float) -> Void)?
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
    }

    // MARK: - Lifecycle

    public func requestAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    public func start() {
        sessionQueue.async { [weak self] in
            self?.configure()
            guard self?.session.isRunning == false else { return }
            self?.session.startRunning()
        }
    }

    public func stop() {
        sessionQueue.async { [weak self] in
            guard self?.session.isRunning == true else { return }
            self?.session.stopRunning()
        }
    }

    // MARK: - Configuration

    private func configure() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        // Rear wide camera.
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video, position: .back) else {
            Log.camera.error("No rear wide camera.")
            return
        }
        videoDevice = device

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }
        } catch {
            Log.camera.error("Input error: \(error.localizedDescription, privacy: .public)")
            return
        }

        // Photo output (HDR HEIC).
        let photoOutput = AVCapturePhotoOutput()
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
            // Store photos upright (portrait) so the stitcher can load raw pixels
            // without worrying about EXIF rotation.
            if let connection = photoOutput.connection(with: .video) {
                if #available(iOS 17.0, *) {
                    connection.videoRotationAngle = 90 // portrait
                } else {
                    connection.videoOrientation = .portrait
                }
            }
        }
        self.photoOutput = photoOutput

        // Video output for sharpness sampling.
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            videoOutput.setSampleBufferDelegate(sampleProxy,
                                                queue: DispatchQueue(label: "com.teleport.camera.video"))
        }
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
    public func capturePhoto() async throws -> AVCapturePhoto {
        guard let photoOutput else { throw CameraError.configurationFailed }
        let settings = makePhotoSettings(output: photoOutput)
        return try await withCheckedThrowingContinuation { continuation in
            // The photo output retains the delegate for the duration of the capture.
            let delegate = PhotoCaptureDelegate(continuation: continuation)
            photoOutput.capturePhoto(with: settings, delegate: delegate)
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
        return CameraIntrinsics(fx: fx, fy: fx,
                                cx: Float(width) / 2, cy: Float(height) / 2)
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
