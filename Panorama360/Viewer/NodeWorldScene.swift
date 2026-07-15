import Foundation
import SceneKit
import CoreMotion
import simd
import ImageIO
import UIKit

/// The "Live 3D Projection Scanner" world. Builds a cyan wireframe grid of
/// target nodes on a sphere, then progressively replaces each node with a real
/// 256-px photo as it is scanned — directly, in the live view, with no stitch.
///
/// **Spatial mapping.** Node positions, the camera target and the magnetic-lock
/// ray all share one spherical projection:
///   `x = r·cos(θ)·sin(φ)`, `y = r·sin(θ)`, `z = r·cos(θ)·cos(φ)`
/// with θ = pitch, φ = yaw, r = 2.0. Feeding the CoreMotion-derived `(pitch,
/// yaw)` through that same map for both the nodes and the camera keeps the
/// device attitude perfectly registered to the world.
final class NodeWorldScene {

    private static let cyanColor = UIColor(red: 0.20, green: 0.85, blue: 1.0, alpha: 1.0)
    private static let goldColor = UIColor(red: 1.0, green: 0.78, blue: 0.25, alpha: 1.0)
    private static let radius: Float = 2.0           // r in the mapping formula
    private static let nodeRadius: CGFloat = 0.085
    /// Magnetic-lock angular variance (radians).
    static let lockThreshold: Float = 0.12

    private let scene = SCNScene()
    private let cameraNode: SCNNode
    private let motion = CMMotionManager()

    private var nodes: [UUID: SCNNode] = [:]
    private var directions: [UUID: SIMD3<Float>] = [:]   // unit vectors
    private var captured: Set<UUID> = []
    private(set) var lockedNodeID: UUID?
    private var contracting: UUID?

    // Manual-orbit state (NodeGalaxyView path).
    private var yaw: Float = 0
    private var pitch: Float = 0
    private var fov: CGFloat = 60

    // MARK: - Init

    private init() {
        let cam = SCNCamera()
        cam.fieldOfView = fov
        cam.zNear = 0.05
        cameraNode = SCNNode()
        cameraNode.camera = cam
        cameraNode.simdPosition = .zero
        scene.rootNode.addChildNode(cameraNode)
        scene.background.contents = UIColor.black
    }

    /// Live scanner: a dark wireframe grid of the target points.
    convenience init(points: [CapturePoint]) {
        self.init()
        buildNodes(points.map { ($0.id, Float($0.pitch), Float($0.yaw)) })
        buildMesh()
        pointCameraForward()
    }

    /// Galaxy view: nodes pre-textured from already-captured photos.
    convenience init(samples: [CaptureSample]) {
        self.init()
        buildNodes(samples.map { ($0.id, Float($0.pitch), Float($0.yaw)) })
        buildMesh()
        for s in samples {
            if let img = thumbnail(of: s.imageURL) { applyTexture(nodeID: s.id, img) }
        }
        pointCameraForward()
    }

    // MARK: - SCNView

    func makeView() -> SCNView {
        let view = SCNView()
        view.scene = scene
        view.backgroundColor = .black
        view.allowsCameraControl = false   // we drive the camera ourselves
        view.antialiasingMode = .multisampling4X
        view.pointOfView = cameraNode
        return view
    }

    // MARK: - Build

    private func buildNodes(_ specs: [(UUID, Float, Float)]) {
        for (id, p, y) in specs {
            let dir = project(pitch: p, yaw: y)
            directions[id] = dir
            let sphere = SCNSphere(radius: Self.nodeRadius)
            sphere.firstMaterial = wireframeMaterial()
            let node = SCNNode(geometry: sphere)
            node.simdPosition = dir * Self.radius
            nodes[id] = node
            scene.rootNode.addChildNode(node)
        }
    }

    /// The canonical spherical projection → unit cartesian.
    private func project(pitch: Float, yaw: Float) -> SIMD3<Float> {
        let cp = cos(pitch)
        return SIMD3<Float>(cp * sin(yaw), sin(pitch), cp * cos(yaw))
    }

    private func wireframeMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = Self.cyanColor.withAlphaComponent(0.12)
        m.emission.contents = Self.cyanColor.withAlphaComponent(0.55)
        m.transparency = 0.8
        m.isDoubleSided = true
        return m
    }

    /// Low-opacity grid lines, each node linked to its two nearest neighbours.
    private func buildMesh() {
        let ids = Array(directions.keys)
        guard ids.count > 1 else { return }
        var verts: [SCNVector3] = []
        for id in ids {
            let here = directions[id]!
            let ranked = ids.filter { $0 != id }
                .map { ($0, simd_distance(here, directions[$0]!)) }
                .sorted { $0.1 < $1.1 }
            for (nid, _) in ranked.prefix(2) {
                verts.append(Self.scn(here * Self.radius))
                verts.append(Self.scn(directions[nid]! * Self.radius))
            }
        }
        let source = SCNGeometrySource(vertices: verts)
        let indices: [Int32] = (0..<verts.count).map { Int32($0) }
        let data = indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(data: data, primitiveType: .line,
                                         primitiveCount: verts.count / 2, bytesPerIndex: 4)
        let geo = SCNGeometry(sources: [source], elements: [element])
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = Self.cyanColor.withAlphaComponent(0.18)
        m.emission.contents = Self.cyanColor.withAlphaComponent(0.18)
        m.transparency = 0.35
        geo.firstMaterial = m
        scene.rootNode.addChildNode(SCNNode(geometry: geo))
    }

    // MARK: - Transactional node texturing

    /// Projects `image` straight onto the node's diffuse material and marks it
    /// scanned (gold glow). Called the instant a 256 thumbnail arrives.
    func applyTexture(nodeID: UUID, _ image: UIImage) {
        guard let node = nodes[nodeID] else { return }
        captured.insert(nodeID)
        let m = node.geometry?.firstMaterial
        m?.diffuse.contents = image
        m?.emission.contents = Self.goldColor.withAlphaComponent(0.35)
        m?.transparency = 1.0
        node.scale = SCNVector3Make(1, 1, 1)
        if lockedNodeID == nodeID { lockedNodeID = nil }
    }

    // MARK: - Magnetic locking engine

    /// Angular test: the focal ray (device attitude) vs every uncaptured node.
    /// Returns the nearest node within `lockThreshold`, else nil.
    func evaluateLock(orientation: DeviceOrientation) -> (UUID, Float)? {
        let ray = project(pitch: Float(orientation.pitch), yaw: Float(orientation.yaw))
        var bestID: UUID?
        var bestAngle: Float = Self.lockThreshold
        for (id, dir) in directions where !captured.contains(id) {
            let d = max(-1, min(1, simd_dot(ray, dir)))
            let angle = acos(d)
            if angle < bestAngle { bestAngle = angle; bestID = id }
        }
        return bestID.map { ($0, bestAngle) }
    }

    /// Engages the magnetic clamp on `id` (eases the node toward its locked
    /// scale); passing nil releases the previous node back to rest.
    func setLocked(_ id: UUID?) {
        if let prev = lockedNodeID, prev != id { contracting = prev }
        lockedNodeID = id
    }

    /// Returns true iff a **new** node entered the magnetic band this tick (the
    /// caller then fires the snap haptic). Drives the clamp transition internally
    /// so the caller needs no per-frame bookkeeping.
    @discardableResult
    func updateMagneticLock(orientation: DeviceOrientation) -> Bool {
        if let (id, _) = evaluateLock(orientation: orientation) {
            if id != lockedNodeID {
                setLocked(id)
                return true
            }
            return false
        }
        if lockedNodeID != nil { setLocked(nil) }
        return false
    }

    // MARK: - Camera (attitude / drag / gyro)

    /// Drives the camera from CoreMotion-derived attitude, then advances the
    /// exponential magnetic clamp on the locked node.
    func applyAttitude(_ orientation: DeviceOrientation) {
        let target = project(pitch: Float(orientation.pitch),
                             yaw: Float(orientation.yaw)) * Self.radius
        cameraNode.simdLook(at: target)
        easeNodes()
    }

    func drag(by translation: CGSize) {
        yaw += Float(translation.width) * 0.004
        pitch -= Float(translation.height) * 0.004
        pitch = max(-1.45, min(1.45, pitch))
        cameraNode.simdLook(at: project(pitch: pitch, yaw: yaw) * Self.radius)
    }

    func zoom(scale: CGFloat) {
        fov = max(30, min(90, fov / scale))
        cameraNode.camera?.fieldOfView = fov
    }

    /// Own-gyro path (NodeGalaxyView browsing). The live scanner drives the
    /// camera from the view-model's motion instead.
    func setGyroEnabled(_ enabled: Bool) {
        guard enabled else { motion.stopDeviceMotionUpdates(); return }
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let att = data?.attitude else { return }
            let p = Float(att.pitch), y = Float(att.yaw)
            self.cameraNode.simdLook(at: self.project(pitch: p, yaw: y) * Self.radius)
        }
    }

    // MARK: - Private

    private func pointCameraForward() {
        cameraNode.simdLook(at: SIMD3<Float>(0, 0, Self.radius)) // +Z = forward node
    }

    /// Exponential ease: locked node → 1.5×, the just-released node → 1.0×.
    private func easeNodes() {
        if let id = lockedNodeID, let node = nodes[id] {
            ease(node, toward: 1.5)
        }
        if let id = contracting, let node = nodes[id] {
            ease(node, toward: 1.0)
            if abs(node.scale.x - 1.0) < 0.02 {
                node.scale = SCNVector3Make(1, 1, 1)
                contracting = nil
            }
        }
    }

    private func ease(_ node: SCNNode, toward target: Float) {
        let next = node.scale.x + (target - node.scale.x) * 0.2
        node.scale = SCNVector3Make(next, next, next)
    }

    /// 256 px thumbnail of an archived photo (galaxy-view init only).
    private func thumbnail(of url: URL) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 256,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }

    private static func scn(_ v: SIMD3<Float>) -> SCNVector3 { SCNVector3Make(v.x, v.y, v.z) }
}
