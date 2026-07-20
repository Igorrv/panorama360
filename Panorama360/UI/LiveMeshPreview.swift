import SwiftUI
import MetalKit
import UIKit

/// Picture-in-picture Metal surface that shows the live, growing 360° globe
/// during capture. Hosts a `SpatialFragmentRenderer` and a
/// `LiveReconstructionManager`, which **share one `MTLDevice` and one
/// `MTLCommandQueue`** — this is the cross-queue-hazard fix: Metal serializes
/// the manager's writes against the renderer's reads only because they share a
/// queue.
///
/// The `Coordinator` retains *both* objects: the renderer (the MTKView delegate
/// is weak) and the manager (it owns the preview texture the renderer samples).
struct LiveMeshPreview: UIViewRepresentable {

    /// Delivered once the Metal objects are built so the view-model can push
    /// orientation to the renderer and captured samples to the manager.
    let onReady: (SpatialFragmentRenderer, LiveReconstructionManager) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.enableSetNeedsDisplay = false
        view.isPaused = false                  // continuous rendering
        // ProMotion (iPhone Pro) ⇒ 120 Hz; capped to the device's max elsewhere.
        view.preferredFramesPerSecond = min(120, UIScreen.main.maximumFramesPerSecond)
        view.backgroundColor = .black

        guard let device = view.device,
              let commandQueue = device.makeCommandQueue(),
              // Build the manager first — the renderer samples its preview texture.
              let manager = LiveReconstructionManager.create(device: device, commandQueue: commandQueue),
              let renderer = SpatialFragmentRenderer(device: device,
                                                     commandQueue: commandQueue,
                                                     previewTexture: manager.previewTexture) else {
            Log.recon.error("Live globe unavailable — capture proceeds without it.")
            return view
        }

        // Retain both: the delegate is weak, and the manager owns previewTexture.
        context.coordinator.renderer = renderer
        context.coordinator.manager = manager
        view.delegate = renderer
        onReady(renderer, manager)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}

    final class Coordinator {
        var renderer: SpatialFragmentRenderer?
        var manager: LiveReconstructionManager?
    }
}
