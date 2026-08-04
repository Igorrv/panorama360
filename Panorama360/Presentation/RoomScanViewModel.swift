import Foundation
import SwiftUI
import RealityKit
import ARKit

/// Backs the LiDAR 3D scan: runs the scene-reconstruction config on the `ARView`,
/// polls `currentFrame.anchors` into a `RoomScanner` (no delegate — RealityKit
/// owns the session delegate), and on finish merges + persists the mesh. Mirrors
/// the `CaptureViewModel` lifecycle (start/suspend/resume + onComplete/onCancel).
@MainActor
public final class RoomScanViewModel: ObservableObject {

    /// Live count of distinct mesh areas captured so far.
    @Published public private(set) var meshAreaCount: Int = 0
    /// Colour coverage 0…1 (fraction of vertices with enough accumulated colour).
    @Published public private(set) var coverage: Float = 0
    /// pt-BR coaching text — changes as coverage grows.
    @Published public var status: String = "Aponte a câmera e vasculhe o cômodo em círculo, devagar."
    @Published public var errorMessage: String?

    public var onComplete: ((URL?) -> Void)?
    public var onCancel: (() -> Void)?
    public let projectID: UUID

    private let scanner = RoomScanner()
    private let texturizer = MeshTexturizer()
    private let store = MeshStore()
    private weak var arView: ARView?
    private var pollTask: Task<Void, Never>?

    public init(projectID: UUID) { self.projectID = projectID }

    /// Receives the `ARView` from `RoomScanSurface` once it is built.
    public func attach(_ view: ARView) {
        arView = view
    }

    // MARK: - Lifecycle

    public func start() {
        guard let arView else { return }
        guard let config = RoomScanner.makeConfiguration() else {
            errorMessage = "Este dispositivo não suporta escaneamento 3D (requer LiDAR)."
            return
        }
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        startPolling()
    }

    /// Polls the current frame's anchors ~3×/s into the scanner. Avoids
    /// installing an `ARSessionDelegate` (RealityKit owns it for rendering).
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard let self, let frame = self.arView?.session.currentFrame else { continue }
                self.scanner.ingest(frame.anchors)
                self.texturizer.accumulate(frame: frame)
                let count = self.scanner.anchorCount
                let cov = self.texturizer.coverage()
                if count != self.meshAreaCount {
                    self.meshAreaCount = count
                    self.status = self.coaching(for: count, coverage: cov)
                }
                if abs(cov - self.coverage) > 0.04 {
                    self.coverage = cov
                }
            }
        }
    }

    public func suspend() {
        pollTask?.cancel()
        arView?.session.pause()
    }

    public func resume() { start() }

    public func cancel() {
        pollTask?.cancel()
        arView?.session.pause()
        onCancel?()
    }

    /// Merges the collected mesh and persists it; `onComplete` fires with the
    /// file URL (or nil if nothing was captured, surfaced via `errorMessage`).
    public func finish() {
        pollTask?.cancel()
        // One last colour pass on the live frame before tearing down the session.
        if let frame = arView?.session.currentFrame {
            texturizer.accumulate(frame: frame)
        }
        arView?.session.pause()
        guard let mesh = scanner.merged(using: texturizer) else {
            errorMessage = "Nenhuma malha capturada. Vasculhe o cômodo antes de finalizar."
            return
        }
        do {
            let url = try store.save(mesh, for: projectID)
            Haptics.shared.aligned()
            onComplete?(url)
        } catch {
            errorMessage = "Falha ao salvar o 3D: \(error.localizedDescription)"
        }
    }

    /// pt-BR coaching that nudges the user toward fuller colour coverage.
    private func coaching(for count: Int, coverage: Float) -> String {
        if count == 0 {
            return "Aponte a câmera e vasculhe o cômodo em círculo, devagar."
        }
        if coverage < 0.35 {
            return "\(count) áreas · aproxime-se das superfícies para capturar cor."
        }
        if coverage < 0.7 {
            return "\(count) áreas · vasculhe os cantos e dê a volta nos móveis."
        }
        return "\(count) áreas mapeadas — cobertura boa, pode finalizar."
    }

    public func dismissError() { errorMessage = nil }
}
