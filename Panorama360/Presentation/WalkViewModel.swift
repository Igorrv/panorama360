import Foundation
import SwiftUI
import RealityKit
import ARKit
import Combine
import simd

/// Backs the 3D walk-through viewer: loads the saved `RoomMesh`, builds a lit
/// `ModelEntity`, and drives a virtual **6DOF camera** (drag to look, joystick to
/// move) over a per-frame `SceneEvents.Update`. v1 is free-fly at a fixed height
/// (no collision); the mesh is lit `SimpleMaterial`, not textured. Uses a
/// non-AR `ARView` so there is no live session.
@MainActor
public final class WalkViewModel: ObservableObject {

    @Published public var status: String = "Carregando 3D…"
    @Published public var errorMessage: String?
    public let projectID: UUID

    private let store = MeshStore()
    private weak var arView: ARView?
    private var cameraEntity: Entity?
    private var updateCancellable: Cancellable?

    // 6DOF input state.
    private var move = CGVector(dx: 0, dy: 0)
    private var yaw: Float = 0
    private var pitch: Float = 0
    private var position: SIMD3<Float> = .zero
    private var collider: MeshCollider?
    private static let speed: Float = 1.8      // m/s
    private static let dt: Float = 1.0 / 60.0
    private static let eyeHeight: Float = 1.6  // metres — keeps the camera at head height
    private static let playerRadius: Float = 0.2

    public init(projectID: UUID) { self.projectID = projectID }

    public func attach(_ view: ARView) {
        arView = view
        view.environment.background = .color(.black)
        loadAndBuild()
    }

    public func detach() {
        updateCancellable?.cancel()
        updateCancellable = nil
        arView?.scene.anchors.removeAll()
    }

    // MARK: - Input

    public func setMove(_ v: CGVector) { move = v }

    /// Drag deltas (radians-ish) applied to look.
    public func look(deltaYaw: Float, deltaPitch: Float) {
        yaw += deltaYaw
        pitch = max(-1.4, min(1.4, pitch + deltaPitch))
    }

    public func resetView() {
        yaw = 0; pitch = 0
        let fy = collider?.floorHeight(x: 0, z: 0, fromY: 3) ?? 0
        position = SIMD3<Float>(0, fy + Self.eyeHeight, 0)
        applyCamera()
    }

    // MARK: - Build

    private func loadAndBuild() {
        guard let arView else { return }
        guard let mesh = store.load(for: projectID) else {
            errorMessage = "Nenhum 3D salvo para este projeto. Faça um escaneamento primeiro."
            status = ""
            return
        }
        collider = MeshCollider(mesh)
        guard let resource = buildResource(mesh) else {
            errorMessage = "Não foi possível montar a malha 3D."
            status = ""
            return
        }
        // Vertex colours carry the captured photo: unlit keeps them faithful
        // (no harsh grey shading). Legacy uncoloured meshes keep the lit fallback.
        let material: Material
        if mesh.colors.isEmpty {
            var lit = SimpleMaterial()
            lit.color = .init(tint: UIColor(white: 0.82, alpha: 1.0), texture: nil)
            lit.metallic = .init(floatLiteral: 0.0)
            lit.roughness = .init(floatLiteral: 0.55)
            material = lit
        } else {
            material = UnlitMaterial(color: .white)
        }
        let entity = ModelEntity(mesh: resource, materials: [material])

        let anchor = AnchorEntity(world: matrix_identity_float4x4)
        addLights(to: anchor)
        anchor.addChild(entity)
        arView.scene.addAnchor(anchor)

        // Virtual camera.
        let camAnchor = AnchorEntity(world: matrix_identity_float4x4)
        let camEntity = Entity()
        var cam = PerspectiveCamera()
        cam.camera.far = 100
        cam.camera.near = 0.02
        camEntity.components.set(cam)
        camAnchor.addChild(camEntity)
        arView.scene.addAnchor(camAnchor)
        cameraEntity = camEntity

        let floorY = collider?.floorHeight(x: 0, z: 0, fromY: 3) ?? 0
        position = SIMD3<Float>(0, floorY + Self.eyeHeight, 0)
        applyCamera()
        startUpdates()
        status = "Arraste para olhar · joystick para andar"
    }

    private func buildResource(_ mesh: RoomMesh) -> MeshResource? {
        var desc = MeshDescriptor()
        desc.positions = MeshBuffers.Positions(unflatten(mesh.positions))
        desc.primitives = .triangles(mesh.faces)
        if !mesh.normals.isEmpty {
            desc.normals = MeshBuffers.Normals(unflatten(mesh.normals))
        }
        if !mesh.colors.isEmpty {
            desc.colors = MeshBuffers.Colors(unflattenColors(mesh.colors))
        }
        return try? MeshResource.generate(from: [desc])
    }

    /// RGBA8 (4/vertex) → normalized `[SIMD4<Float>]` for `MeshDescriptor.colors`.
    private func unflattenColors(_ flat: [UInt8]) -> [SIMD4<Float>] {
        let n = flat.count / 4
        var out = [SIMD4<Float>](repeating: .one, count: n)
        for i in 0..<n {
            out[i] = SIMD4<Float>(
                Float(flat[i * 4]) / 255,
                Float(flat[i * 4 + 1]) / 255,
                Float(flat[i * 4 + 2]) / 255,
                Float(flat[i * 4 + 3]) / 255
            )
        }
        return out
    }

    private func unflatten(_ flat: [Float]) -> [SIMD3<Float>] {
        let n = flat.count / 3
        var out = [SIMD3<Float>](repeating: .zero, count: n)
        for i in 0..<n {
            out[i] = SIMD3<Float>(flat[i * 3], flat[i * 3 + 1], flat[i * 3 + 2])
        }
        return out
    }

    private func addLights(to anchor: AnchorEntity) {
        let key = DirectionalLight()
        key.light.intensity = 2500
        key.transform.rotation = simd_quatf(angle: -.pi / 2.6, axis: simd_normalize(SIMD3<Float>(0.6, -1, 0.3)))
        anchor.addChild(key)
        let fill = DirectionalLight()
        fill.light.intensity = 700
        fill.transform.rotation = simd_quatf(angle: .pi / 2.6, axis: simd_normalize(SIMD3<Float>(-0.6, -1, -0.3)))
        anchor.addChild(fill)
    }

    // MARK: - Per-frame camera

    private func startUpdates() {
        updateCancellable = arView?.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        if move.dx != 0 || move.dy != 0 {
            let fwd = horizontalForward()                          // yaw-only, stays planar
            let right = simd_cross(fwd, SIMD3<Float>(0, 1, 0))     // unit (fwd is horizontal)
            let delta = right * (move.dx * Self.speed * Self.dt) + fwd * (move.dy * Self.speed * Self.dt)
            let r = Self.playerRadius
            if collider == nil {
                position += delta
            } else if !collider!.isBlocked(from: position, to: position + delta, radius: r) {
                position += delta
            } else {
                // Blocked diagonally — slide along the wall by axes.
                let xOnly = SIMD3<Float>(position.x + delta.x, position.y, position.z)
                if !collider!.isBlocked(from: position, to: xOnly, radius: r) {
                    position.x = xOnly.x
                }
                let zOnly = SIMD3<Float>(position.x, position.y, position.z + delta.z)
                if !collider!.isBlocked(from: position, to: zOnly, radius: r) {
                    position.z = zOnly.z
                }
            }
        }
        // Gravity: follow the floor directly beneath the camera (head height).
        if let collider, let fy = collider.floorHeight(x: position.x, z: position.z, fromY: position.y + 0.5) {
            position.y = fy + Self.eyeHeight
        }
        applyCamera()
    }

    /// Horizontal look direction from yaw only — looking up/down must not fly you.
    private func horizontalForward() -> SIMD3<Float> {
        SIMD3<Float>(-sin(yaw), 0, -cos(yaw))
    }

    private func applyCamera() {
        guard let cameraEntity else { return }
        var t = Transform()
        t.translation = position
        t.rotation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
            * simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
        cameraEntity.transform = t
    }
}
