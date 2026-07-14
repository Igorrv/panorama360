import Foundation
import SceneKit
import CoreMotion
import simd
import ImageIO
import UIKit

/// Builds + owns the SceneKit "node galaxy": one glowing orb per captured
/// photo, placed on a sphere by the shot's `(pitch, yaw)`, linked by a faint
/// mesh. The camera sits at the centre and orbits by drag or gyro. This is the
/// "malha de nós conectados / point cloud simulada" — deliberately lightweight
/// (each orb textures from a ~256 px thumbnail, never full-res).
final class NodeWorldScene {

    private static let cyanColor = UIColor(red: 0.20, green: 0.85, blue: 1.0, alpha: 1.0)
    private static let sphereRadius: Float = 1.2
    private static let nodeRadius: CGFloat = 0.085

    private let scene = SCNScene()
    private let cameraNode: SCNNode
    private let motion = CMMotionManager()
    private var yaw: Float = 0       // radians, dragged heading
    private var pitch: Float = 0
    private var fov: CGFloat = 60

    init(samples: [CaptureSample]) {
        let cam = SCNCamera()
        cam.fieldOfView = fov
        cam.zNear = 0.05
        cameraNode = SCNNode()
        cameraNode.camera = cam
        cameraNode.position = SCNVector3Zero
        scene.rootNode.addChildNode(cameraNode)

        scene.background.contents = UIColor.black

        let positions = buildNodes(samples)
        buildMesh(positions)
        applyCamera()
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

    @discardableResult
    private func buildNodes(_ samples: [CaptureSample]) -> [SIMD3<Float>] {
        var positions: [SIMD3<Float>] = []
        for sample in samples {
            let dir = simd_normalize(Geometry.sphericalToCartesianf(pitch: sample.pitch, yaw: sample.yaw))
            let pos = dir * Self.sphereRadius
            positions.append(pos)

            let sphere = SCNSphere(radius: Self.nodeRadius)
            let material = SCNMaterial()
            material.lightingModel = .constant                // unlit → reads as a glowing orb
            material.diffuse.contents = thumbnail(of: sample.imageURL) ?? Self.cyanColor
            material.emission.contents = Self.cyanColor.withAlphaComponent(0.35)
            material.isDoubleSided = true
            sphere.firstMaterial = material

            let node = SCNNode(geometry: sphere)
            node.position = SCNVector3Make(pos.x, pos.y, pos.z)
            scene.rootNode.addChildNode(node)
        }
        return positions
    }

    /// Faint cyan links between each node and its two nearest neighbours.
    private func buildMesh(_ positions: [SIMD3<Float>]) {
        guard positions.count > 1 else { return }
        var verts: [SCNVector3] = []
        for i in positions.indices {
            let ranked = positions.enumerated()
                .filter { $0.offset != i }
                .sorted { simd_distance(positions[i], $0.element) < simd_distance(positions[i], $1.element) }
            for nbr in ranked.prefix(2) {
                verts.append(Self.scn(positions[i]))
                verts.append(Self.scn(positions[nbr.offset]))
            }
        }
        let source = SCNGeometrySource(vertices: verts)
        let indices: [Int32] = (0..<verts.count).map { Int32($0) }
        let indexData = indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let element = SCNGeometryElement(data: indexData,
                                         primitiveType: .line,
                                         primitiveCount: verts.count / 2,
                                         bytesPerIndex: 4)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = Self.cyanColor.withAlphaComponent(0.25)
        material.emission.contents = Self.cyanColor.withAlphaComponent(0.25)
        material.transparency = 0.4
        geometry.firstMaterial = material
        scene.rootNode.addChildNode(SCNNode(geometry: geometry))
    }

    // MARK: - Navigation (drag / zoom / gyro)

    func drag(by translation: CGSize) {
        yaw -= Float(translation.width) * 0.005
        pitch -= Float(translation.height) * 0.005
        pitch = max(-1.45, min(1.45, pitch))
        applyCamera()
    }

    func zoom(scale: CGFloat) {
        fov = max(30, min(90, fov / scale))
        cameraNode.camera?.fieldOfView = fov
    }

    func setGyroEnabled(_ enabled: Bool) {
        guard enabled else { motion.stopDeviceMotionUpdates(); return }
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let att = data?.attitude else { return }
            // Mirrors ViewerEngine's gyro mapping (proven sign conventions).
            self.yaw = -Float(att.yaw) * 0.8
            self.pitch = Float(att.pitch) * 0.8
            self.applyCamera()
        }
    }

    private func applyCamera() {
        cameraNode.eulerAngles = SCNVector3Make(pitch, yaw, 0)
    }

    // MARK: - Helpers

    /// ~256 px thumbnail of the saved photo — keeps GPU memory tiny per node.
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
