import SwiftUI
import RealityKit

/// RealityKit `ARView` surface for the LiDAR scan. The live camera passthrough
/// (the real room) renders automatically in `.ar` mode while the mesh is
/// collected silently by polling `currentFrame.anchors` (see
/// `RoomScanViewModel`). `automaticallyConfigureSession` is OFF so the
/// view-model owns the scene-reconstruction config. Mirrors the
/// `UIViewRepresentable` + `onReady` shape of `MetalContainer`/`LiveMeshPreview`.
struct RoomScanSurface: UIViewRepresentable {

    /// Delivered once the `ARView` is built so the view-model can run its config.
    let onReady: (ARView) -> Void

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero,
                          cameraMode: .ar,
                          automaticallyConfigureSession: false)
        view.backgroundColor = .black
        view.contentMode = .scaleAspectFill
        onReady(view)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
