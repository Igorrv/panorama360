import Foundation
import SwiftUI
import Combine
import os

/// Drives the capture screen: wires the camera, motion and guide, runs the
/// auto-capture gate, persists photos, and reports progress to SwiftUI.
@MainActor
public final class CaptureViewModel: ObservableObject {

    // MARK: - Published UI state

    @Published public private(set) var fractionComplete: Double = 0
    @Published public private(set) var capturedCount: Int = 0
    @Published public private(set) var totalPoints: Int = 0
    @Published public private(set) var etaSeconds: Double = 0
    @Published public private(set) var stabilityScore: Double = 0
    @Published public private(set) var reticle: ReticleState = .far
    @Published public private(set) var isReady: Bool = false
    @Published public private(set) var isCapturing: Bool = false
    @Published public private(set) var errorMessage: String?

    // MARK: - Dependencies

    public let guide: CaptureGuide
    public let camera = CameraEngine()
    public let motion = MotionEngine()
    public private(set) var session: PanoramaSession?

    private let store: SessionStore
    private let captureManager: CaptureManager
    private let gate = CaptureGate()
    private var stability = StabilityEstimator()
    private var sessionStartTime: Double = 0
    private var lastCaptureTime: Double = 0
    private var captureIntervals: [Double] = []
    private let cooldown: Double = 0.6
    private var evaluateTask: Task<Void, Never>?
    private var fovConfigured = false

    /// Lock-protected sharpness written from the camera's video queue and read
    /// by the ~15 Hz gate on the main actor. `OSAllocatedUnfairLock` is Sendable,
    /// so the callback captures the lock itself (not `self`) — no main-actor hop.
    private let sharpnessLock = OSAllocatedUnfairLock(initialState: Float(0))
    private var latestOrientation: DeviceOrientation?
    private var latestStability = Stability(score: 0, angularSpeed: 0, isStable: false)

    // Routing closures (set by the container).
    public var onComplete: ((PanoramaSession) -> Void)?
    public var onCancel: (() -> Void)?

    // MARK: - Init

    public init(distribution: SphereDistribution = .default, store: SessionStore = SessionStore()) {
        self.guide = CaptureGuide(distribution: distribution)
        self.store = store
        self.captureManager = CaptureManager(camera: camera, store: store)
        let lock = sharpnessLock
        camera.onSharpness = { score in lock.withLock { $0 = score } }
    }

    // MARK: - Lifecycle

    public func start() async {
        totalPoints = guide.totalPoints
        let authorized = await camera.requestAuthorization()
        guard authorized else { errorMessage = "Camera permission is required."; return }

        let id = UUID()
        do {
            let dir = try store.makeSessionDirectory(id: id)
            session = PanoramaSession(distribution: guide.distribution,
                                      points: guide.points,
                                      directoryURL: dir)
        } catch {
            errorMessage = "Could not create a session directory."
            return
        }

        camera.start()
        Haptics.shared.prepare()

        motion.onUpdate = { [weak self] orient in
            Task { @MainActor in self?.handle(orient) }
        }
        motion.onReferenceSet = { Haptics.shared.approaching() }
        do {
            try motion.start()
        } catch {
            errorMessage = "Motion sensors unavailable."
            return
        }

        sessionStartTime = Date().timeIntervalSince1970
        isReady = true
        startEvaluating()
    }

    public func cancel() {
        evaluateTask?.cancel()
        evaluateTask = nil
        motion.stop()
        camera.stop()
        Haptics.shared.cancelled()
        onCancel?()
    }

    /// Clears the current error banner.
    public func dismissError() { errorMessage = nil }

    // MARK: - Per-frame handling

    public func setViewport(_ size: CGSize) {
        guide.viewport = size
    }

    private func handle(_ orientation: DeviceOrientation) {
        latestOrientation = orientation
        latestStability = stability.ingest(orientation)
        stabilityScore = latestStability.score
        guide.update(orientation: orientation)
        reticle = guide.reticle
        configureFOVIfNeeded()
    }

    private func configureFOVIfNeeded() {
        guard !fovConfigured, let device = camera.videoDevice else { return }
        let fov = device.activeFormat.videoFieldOfView * .pi / 180
        if fov > 0 { guide.horizontalFOV = Double(fov) }
        fovConfigured = true
    }

    private var latestSharpness: Float { sharpnessLock.withLock { $0 } }

    // MARK: - Gate evaluation

    private func startEvaluating() {
        evaluateTask?.cancel()
        evaluateTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.evaluate()
                try? await Task.sleep(nanoseconds: 66_000_000) // ~15 Hz
            }
        }
    }

    private func evaluate() async {
        guard let orientation = latestOrientation, session != nil else { return }
        let status = camera.currentStatus
        let now = Date().timeIntervalSince1970
        let cooldownElapsed = (now - lastCaptureTime) > cooldown

        let input = CaptureGateInput(
            angularDistanceToTarget: guide.alignment.angularDistance,
            stability: latestStability,
            cameraStatus: status,
            sharpness: latestSharpness,
            cooldownElapsed: cooldownElapsed,
            hasTarget: guide.alignment.pointID != nil
        )

        guard gate.evaluate(input).ready,
              let pid = guide.alignment.pointID,
              let point = guide.points.first(where: { $0.id == pid }) else { return }

        await capture(point: point, orientation: orientation)
    }

    // MARK: - Capture

    private func capture(point: CapturePoint, orientation: DeviceOrientation) async {
        guard !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }

        do {
            let sample = try await captureManager.capture(
                point: point, orientation: orientation, sessionID: session!.id)

            guide.markCaptured(pointID: point.id)
            session?.record(sample: sample, forPointID: point.id)
            try? store.persist(session!)

            Haptics.shared.captured()

            let now = Date().timeIntervalSince1970
            if captureIntervals.isEmpty {
                captureIntervals.append(now - sessionStartTime)
            } else {
                captureIntervals.append(now - lastCaptureTime)
            }
            lastCaptureTime = now
            updateProgress()

            if session?.isCaptureComplete == true {
                evaluateTask?.cancel()
                onComplete?(session!)
            }
        } catch {
            Log.capture.error("Capture failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Progress

    private func updateProgress() {
        capturedCount = guide.capturedCount
        fractionComplete = guide.fractionComplete
        let remaining = Double(totalPoints - capturedCount)
        let avgInterval = captureIntervals.reduce(0, +) / Double(max(captureIntervals.count, 1))
        etaSeconds = remaining * avgInterval
    }
}
