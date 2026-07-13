import SwiftUI
import MetalKit

/// The 360° viewer screen: a Metal sphere you orbit by drag / pinch / gyro.
struct PanoramaViewerView: View {

    let url: URL

    @StateObject private var vm = ViewerViewModel()
    @EnvironmentObject private var router: AppRouter

    @State private var lastDrag: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            MetalContainer(url: url,
                           onReady: { renderer in vm.attach(renderer: renderer) },
                           onResize: { vm.engine.updateAspect($0) })
                .gesture(dragGesture)
                .simultaneousGesture(magnifyGesture)
                .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                hints
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let delta = CGSize(width: value.translation.width - lastDrag.width,
                                   height: value.translation.height - lastDrag.height)
                vm.engine.drag(by: delta)
                lastDrag = value.translation
            }
            .onEnded { _ in lastDrag = .zero }
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in vm.engine.zoom(scale: value) }
    }

    // MARK: - Top bar + hints

    private var topBar: some View {
        HStack {
            Button {
                // Leaving the viewer after the tutorial room = onboarding done →
                // full capture mode unlocked for all future launches.
                if router.tutorialActive { router.completeOnboarding() }
                router.goCapture()
            } label: {
                if router.tutorialActive {
                    Label("Done", systemImage: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).frame(height: 44)
                        .glassPanel(cornerRadius: 22)
                } else {
                    Label("New", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .glassPanel(cornerRadius: 22)
                }
            }
            Spacer()
            Button {
                vm.toggleGyro()
            } label: {
                Image(systemName: "gyroscope")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(vm.engine.gyroEnabled ? .green : .white)
                    .frame(width: 44, height: 44)
                    .glassPanel(cornerRadius: 22)
            }
        }
    }

    private var hints: some View {
        HStack(spacing: 18) {
            Label("Drag to look", systemImage: "hand.draw")
            Label("Pinch to zoom", systemImage: "plus.magnifyingglass")
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(.white.opacity(0.6))
        .padding(.horizontal, 16).padding(.vertical, 10)
        .glassPanel(cornerRadius: 18)
    }
}

// MARK: - Metal container

private struct MetalContainer: UIViewRepresentable {

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
        view.preferredFramesPerSecond = 60
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
