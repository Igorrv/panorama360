import SwiftUI
import MetalKit

/// Shared Metal host for the 360° equirectangular sphere: builds one `MTKView`
/// + `PanoramaRenderer`, loads the initial panorama, and hands the renderer back
/// via `onReady`. Used by both the single-panorama viewer and the tour viewer.
/// Subsequent equirects are swapped in place via `renderer.loadPanogram(at:)`.
struct MetalContainer: UIViewRepresentable {

    let url: URL
    let onReady: (PanoramaRenderer) -> Void
    let onResize: (CGSize) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.enableSetNeedsDisplay = false
        view.isPaused = false                  // continuous rendering
        // ProMotion (iPhone Pro) ⇒ 120 Hz; capped to the device's max elsewhere.
        view.preferredFramesPerSecond = min(120, view.device?.maxFramesPerSecond ?? 60)
        view.backgroundColor = .black

        if let device = view.device, let renderer = PanoramaRenderer(device: device) {
            context.coordinator.renderer = renderer   // retain (delegate is weak)
            renderer.loadPanogram(at: url)
            view.delegate = renderer
            onResize(view.bounds.size)
            onReady(renderer)
        }
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}

    final class Coordinator {
        var renderer: PanoramaRenderer?
    }
}
