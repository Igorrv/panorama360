import Foundation
import SwiftUI
import Combine
import os
import simd

/// Drives the capture screen: wires the camera, motion and guide, runs the
/// auto-capture gate, persists photos, feeds each capture to the live 360°
/// reconstruction, and reports progress to SwiftUI.
///
/// Two modes (see `GuideMode`):
/// - `.fixed` — the tutorial ring; completes when every point is captured.
/// - `.dynamic` — the spatial scanner: one active target at a time, replaced
///   after each capture by the next uncovered direction (coverage-driven), and
///   each photo is added live to the globe. Completes when coverage is reached.
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
    /// Human-readable reason capture isn't firing right now (pt-BR). Shown under
    /// the reticle so a stall is self-diagnosing instead of silent.
    @Published public private(set) var statusHint: String?
    /// Pole prompt (pt-BR) shown when the nearest un-captured target is near the
    /// zenith ("Aponte para o teto") or nadir ("Aponte para o chão") — guides the
    /// user to fill the full-sphere ceiling/floor shots so nothing renders black.
    @Published public private(set) var poleHint: String?
    /// 0..1 capture confidence for the reticle ring (alignment + stability + sharpness).
    @Published public private(set) var captureConfidence: Float = 0
    /// Sphere coverage so far (dynamic mode); drives the progress bar.
    @Published public private(set) var coverageFraction: Double = 0
    @Published public private(set) var coverageComplete: Bool = false
    /// True when the live globe Metal objects were built (false ⇒ degraded,
    /// capture still works without the PiP).
    @Published public private(set) var liveGlobeAvailable: Bool = false

    /// Whether the bottom bar should show coverage % instead of "X de Y".
    public var usesCoverage: Bool { guide.mode == .dynamic }

    /// Whether the active distribution adds zenith/nadir poles (full-sphere).
    public var includesPoles: Bool { guide.distribution.includePoles }
    /// Whether the ceiling (zenith) / floor (nadir) pole shots are captured.
    /// Drives the teto/chão glyphs in the coverage pill; re-read on every redraw
    /// (triggered by `capturedCount` changing after each capture).
    public var ceilingCaptured: Bool { poleCaptured(positive: true) }
    public var floorCaptured: Bool { poleCaptured(positive: false) }

    private func poleCaptured(positive: Bool) -> Bool {
        let target = positive ? Double.pi / 2 : -Double.pi / 2
        return guide.points.contains { abs($0.pitch - target) < 0.01 && $0.isCaptured }
    }

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
    /// Fewest captures before the manual "finish" path appears / proceeds —
    /// stops a single stray shot from producing an all-black panorama.
    private static let minFinishCaptures = 4
    /// Max device rotation (radians) tolerated DURING one HDR exposure. The
    /// `.quality` bracket spans several hundred ms; if the user starts turning in
    /// that window the photo is motion-blurred and its recorded orientation no
    /// longer matches where it was exposed — keeping it would smear the stitch.
    /// Conservative so a steady hold is never false-rejected.
    private static let maxCaptureMotion: Float = 6 * .pi / 180
    private var evaluateTask: Task<Void, Never>?
    private var fovConfigured = false
    private var consecutiveFailures = 0
    private var didComplete = false

    /// Coverage target generator (dynamic mode only), built once the lens FOV is known.
    private var coverage: CoverageAnalyzer?

    /// Live globe (PiP). Set by `attachLiveGlobe` from the `LiveMeshPreview`.
    private var liveRenderer: SpatialFragmentRenderer?
    private var reconstruction: LiveReconstructionManager?

    private let sharpnessLock = OSAllocatedUnfairLock(initialState: Float(0))
    private var latestOrientation: DeviceOrientation?
    private var latestStability = Stability(score: 0, angularSpeed: 0, isStable: false)

    // Routing closures (set by the container).
    public var onComplete: ((PanoramaSession) -> Void)?
    public var onCancel: (() -> Void)?
    /// Stream A bridge: delivers each 256-px thumbnail (nodeUUID → image) the
    /// instant it is extracted, for progressive live node texturing.
    public var onThumbnail: ((UUID, UIImage) -> Void)?

    // MARK: - Init

    public init(mode: GuideMode = .fixed(.default), store: SessionStore = SessionStore()) {
        self.guide = CaptureGuide(mode: mode)
        self.store = store
        self.captureManager = CaptureManager(camera: camera, store: store)
        let lock = sharpnessLock
        camera.onSharpness = { score in lock.withLock { $0 = score } }
        camera.onRuntimeError = { [weak self] detail in
            Task { @MainActor in self?.errorMessage = "Erro de câmera: \(detail)" }
        }
    }

    /// Hands the live-globe Metal objects to the VM (called from LiveMeshPreview.onReady).
    public func attachLiveGlobe(renderer: SpatialFragmentRenderer, manager: LiveReconstructionManager) {
        liveRenderer = renderer
        reconstruction = manager
        liveGlobeAvailable = true
    }

    // MARK: - Lifecycle

    public func start() async {
        totalPoints = guide.totalPoints
        let authorized = await camera.requestAuthorization()
        guard authorized else { errorMessage = "É preciso permitir o acesso à câmera."; return }

        let id = UUID()
        do {
            let dir = try store.makeSessionDirectory(id: id)
            let newSession = PanoramaSession(id: id,
                                             distribution: guide.distribution,
                                             points: guide.points,
                                             directoryURL: dir)
            try store.persist(newSession)
            session = newSession
        } catch {
            errorMessage = "Não foi possível criar ou salvar a sessão."
            return
        }

        do {
            try await camera.start()
        } catch {
            errorMessage = "Não foi possível iniciar a câmera: \(error.localizedDescription)"
            return
        }
        Haptics.shared.prepare()

        // Stream A: forward each 256 thumbnail (nodeUUID → image) to the live
        // scanner the instant it is extracted, on the main actor.
        await captureManager.setThumbnailHandler { [weak self] id, image in
            Task { @MainActor in self?.onThumbnail?(id, image) }
        }

        motion.onUpdate = { [weak self] orient in
            Task { @MainActor in self?.handle(orient) }
        }
        motion.onReferenceSet = { Haptics.shared.approaching() }
        do {
            try motion.start()
        } catch {
            errorMessage = "Sensores de movimento indisponíveis."
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

    /// Suspends capture when backgrounded. iOS kills apps that keep the camera
    /// running while suspended, so the camera must stop — but CoreMotion is
    /// intentionally LEFT RUNNING. Stopping/restarting device-motion re-establishes
    /// the `xArbitraryZVertical` heading origin and would shift the session frame,
    /// breaking alignment between photos taken before and after the pause. While
    /// suspended iOS pauses delivery anyway; on resume, updates continue in the
    /// SAME frame, so every photo's quaternion stays consistent. The live globe is
    /// not torn down — its textures persist and resume on foreground.
    public func suspend() {
        evaluateTask?.cancel()
        evaluateTask = nil
        camera.stop()
    }

    /// Resumes after foregrounding. CoreMotion was left running across the
    /// suspension, so it is restarted ONLY if the system actually stopped it —
    /// and the reference frame is NEVER reset. Re-anchoring the heading would
    /// misalign every post-resume photo with the ones captured before the pause.
    public func resume() {
        guard isReady, session != nil else { return }
        if !motion.isRunning {
            do {
                try motion.start()
            } catch {
                errorMessage = "Sensores de movimento indisponíveis."
                return
            }
        }
        Task { try? await camera.start() }
        startEvaluating()
    }

    /// Manual escape hatch: stop capturing and proceed to stitching with the
    /// photos taken so far (≥1).
    public func finishCapture() {
        guard let session else {
            errorMessage = "Sessão ainda não iniciada."
            return
        }
        guard guide.capturedCount >= Self.minFinishCaptures else {
            errorMessage = "Vire devagar mirando nos pontos para cobrir todo o ambiente — mínimo de \(Self.minFinishCaptures) fotos antes de montar o 360°."
            return
        }
        Haptics.shared.captured()
        completeCapture(with: session)
    }

    /// Manual capture: fires immediately for the target you're aiming at,
    /// bypassing the stability/sharpness blockers (the auto-gate can stall in low
    /// light or with minor shake) but keeping the cooldown so it can't spam. The
    /// photo lands on the globe at your real aim direction — lets you deliberately
    /// "scan this section." The point captured is the nearest un-captured guide
    /// target, already tracked each frame in `guide.alignment.pointID`.
    public func captureNow() async {
        guard !isCapturing, session != nil, let orientation = latestOrientation else { return }
        let now = Date().timeIntervalSince1970
        guard (now - lastCaptureTime) > cooldown else { return }
        guard let pid = guide.alignment.pointID,
              let point = guide.points.first(where: { $0.id == pid }) else { return }
        await capture(point: point, orientation: orientation)
    }

    public var canFinish: Bool { guide.capturedCount >= Self.minFinishCaptures }

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
        // The live globe tracks the device.
        liveRenderer?.updateOrientation(orientation)
        configureFOVIfNeeded()
    }

    /// The guide projects targets onto the *screen*, so it needs the portrait
    /// horizontal FOV — not the sensor's landscape one, which drew every dot
    /// off to the side of the object it was meant to sit on. Coverage uses the
    /// narrow half-FOV so a shot is never credited with more sphere than it saw.
    private func configureFOVIfNeeded() {
        guard !fovConfigured, let fov = camera.photoFOV else { return }
        guide.horizontalFOV = fov.horizontal
        fovConfigured = true
        if guide.mode == .dynamic, coverage == nil {
            coverage = CoverageAnalyzer(halfFOV: fov.narrowHalf)
        }
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

        let output = gate.evaluate(input)
        statusHint = hint(for: output.blockers, ready: output.ready)
        poleHint = poleHint(for: guide.alignment.pointID)
        captureConfidence = CaptureConfidenceEngine.combine(
            alignment: guide.alignment.confidence,
            stability: latestStability.score,
            sharpness: latestSharpness,
            minSharpness: gate.minSharpness)

        guard output.ready,
              let pid = guide.alignment.pointID,
              let point = guide.points.first(where: { $0.id == pid }) else { return }

        await capture(point: point, orientation: orientation)
    }

    /// Turns the gate's blockers into a one-line Portuguese instruction.
    private func hint(for blockers: [CaptureGateOutput.Blocker], ready: Bool) -> String? {
        if ready { return nil }
        if coverageComplete { return "Cobertura completa — toque em Finalizar" }
        guard let first = blockers.first else { return nil }
        switch first {
        case .noTarget:           return "Mire em um ponto brilhante"
        case .notAligned:         return "Centralize o ponto"
        case .moving:             return "Fique parado"
        case .adjustingFocus:     return "Fique parado — focando"
        case .adjustingExposure:  return "Fique parado — exposição"
        case .blurry:             return "Muito escuro/tremido — mais luz"
        case .cooldown:           return nil   // transient; don't show
        }
    }

    /// "Aponte para o teto/chão" when the active target is within ~20° of a pole.
    private func poleHint(for pointID: UUID?) -> String? {
        guard let pid = pointID,
              let point = guide.points.first(where: { $0.id == pid }) else { return nil }
        let pole = radians(70)
        if point.pitch > pole { return "Aponte para o teto" }
        if point.pitch < -pole { return "Aponte para o chão" }
        return nil
    }

    // MARK: - Capture + live reconstruction

    private func capture(point: CapturePoint, orientation: DeviceOrientation) async {
        guard !isCapturing else { return }
        guard var session = self.session else { return }
        isCapturing = true
        defer { isCapturing = false }

        let sample: CaptureSample
        do {
            sample = try await captureManager.capture(
                point: point, orientation: orientation, sessionID: session.id)
        } catch {
            consecutiveFailures += 1
            Log.capture.error("Capture failed: \(error.localizedDescription, privacy: .public)")
            if consecutiveFailures >= 3 {
                errorMessage = "A captura está falhando repetidamente (\(error.localizedDescription)). " +
                               "Toque em “Finalizar e montar 360°” para usar as fotos já tiradas."
            }
            return
        }

        // Quality guard: the HDR `.quality` exposure spans several hundred
        // milliseconds. If the device rotated past `maxCaptureMotion` during that
        // window the photo is motion-blurred and was exposed somewhere between the
        // recorded orientation and the current one — keeping it would smear the
        // stitch. Reject it, consume the cooldown, and let the gate re-fire once
        // the user holds still. The threshold is conservative so a steady hand is
        // never false-rejected.
        if let post = latestOrientation {
            let moved = Geometry.angularDistance(orientation.lookDirection, post.lookDirection)
            if moved > Self.maxCaptureMotion {
                lastCaptureTime = Date().timeIntervalSince1970
                consecutiveFailures += 1
                Haptics.shared.cancelled()
                Log.capture.warning("Rejected capture: device rotated \(Int(moved * 180 / .pi))° during exposure")
                if consecutiveFailures >= 3 {
                    errorMessage = "O celular está se movendo durante a foto. Segure firme e parado em cada ponto até a captura concluir."
                }
                return
            }
        }

        // Success — feedback sequence: haptic + shutter sound + green check + globe update.
        consecutiveFailures = 0
        guide.markCaptured(pointID: point.id)
        if guide.mode == .dynamic,
           !session.points.contains(where: { $0.id == point.id }) {
            session.points.append(point)
        }
        session.record(sample: sample, forPointID: point.id)
        self.session = session
        try? store.persist(session)
        Haptics.shared.captured()
        Haptics.shared.shutterSound()

        // Add the photo to the live globe (suspends main actor; UI keeps running).
        await reconstruction?.add(sample)

        // Dynamic mode: update coverage and advance to the next target.
        if guide.mode == .dynamic {
            advanceDynamicCoverage(captured: point)
        }

        let now = Date().timeIntervalSince1970
        captureIntervals.append(captureIntervals.isEmpty ? now - sessionStartTime : now - lastCaptureTime)
        lastCaptureTime = now
        updateProgress()

        // Completion: fixed ring when all captured; dynamic when coverage reached.
        let complete: Bool
        switch guide.mode {
        case .fixed:
            complete = session.isCaptureComplete
        case .dynamic:
            complete = coverageComplete
        }
        if complete {
            completeCapture(with: session)
        }
    }

    /// Ends the capture pipeline exactly once and releases camera/motion before
    /// the memory-heavy stitch begins. Both manual and automatic completion use
    /// this path so neither can leave capture hardware running behind the viewer.
    private func completeCapture(with session: PanoramaSession) {
        guard !didComplete else { return }
        didComplete = true
        evaluateTask?.cancel()
        evaluateTask = nil
        motion.stop()
        camera.stop()
        onComplete?(session)
    }

    /// Records the capture in the coverage analyzer and replaces the active
    /// target with the next uncovered direction (or marks coverage complete).
    private func advanceDynamicCoverage(captured point: CapturePoint) {
        guard var cov = coverage else { return }
        cov.mark(pitch: point.pitch, yaw: point.yaw)
        coverageFraction = cov.coverageFraction
        coverage = cov

        let look = latestOrientation?.lookDirection ?? SIMD3<Float>(0, 0, -1)
        let lookD = SIMD3<Double>(Double(look.x), Double(look.y), Double(look.z))
        if let next = cov.nextTarget(currentLook: lookD) {
            guide.setActiveTarget(pitch: next.pitch, yaw: next.yaw)
        } else {
            coverageComplete = true
        }
    }

    // MARK: - Progress

    private func updateProgress() {
        capturedCount = guide.capturedCount
        if guide.mode == .dynamic {
            fractionComplete = coverageFraction
        } else {
            fractionComplete = guide.fractionComplete
        }
        let remaining = max(0, Double(totalPoints - capturedCount))
        let avgInterval = captureIntervals.reduce(0, +) / Double(max(captureIntervals.count, 1))
        etaSeconds = remaining * avgInterval
    }
}
