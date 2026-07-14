import SwiftUI
import SceneKit

/// The post-capture "node galaxy": the photos you just took, floating as a
/// connected galaxy of glowing nodes in SceneKit. Orbit by dragging, zoom by
/// pinching, or steer with the gyro. One tap runs the full 360° stitch.
struct NodeGalaxyView: View {

    let session: PanoramaSession

    @EnvironmentObject private var router: AppRouter
    @State private var scene: NodeWorldScene
    @State private var gyroOn = false
    @State private var lastDrag: CGSize = .zero
    @State private var lastMagnify: CGFloat = 1

    init(session: PanoramaSession) {
        self.session = session
        // Build the SceneKit world once, up front, from the captured samples.
        _scene = State(initialValue: NodeWorldScene(samples: session.samples))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GalaxyHost(scene: scene)
                .ignoresSafeArea()
                .gesture(dragGesture)
                .gesture(magnifyGesture)

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                Spacer()
                bottomBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }

            // Centre HUD: a faint scanner ring + coverage readout.
            VStack(spacing: 4) {
                HUDRing(tickCount: 48, rotationSeconds: 26,
                        fill: session.fractionComplete, color: Theme.cyan)
                    .frame(width: 58, height: 58)
                    .opacity(0.6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 70)
            .allowsHitTesting(false)
        }
        .tint(Theme.cyan)
        .onAppear { router.completeOnboarding() }
        .onDisappear { scene.setGyroEnabled(false) }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(spacing: 14) {
            Button {
                scene.setGyroEnabled(false)
                router.completeOnboarding()
                router.goCapture()
            } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .glassPanel(cornerRadius: 22)
            }

            Spacer()

            // Node + coverage readout.
            HStack(spacing: 8) {
                Label("\(session.samples.count)", systemImage: "circle.hexagongrid.fill")
                    .font(.App.hud)
                Divider().frame(height: 18).overlay(Color.white.opacity(0.3))
                Text(cov)
                    .font(.App.hud)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .glassPanel(cornerRadius: Theme.R.pill)

            gyroButton
        }
    }

    private var gyroButton: some View {
        Button {
            gyroOn.toggle()
            scene.setGyroEnabled(gyroOn)
        } label: {
            Image(systemName: gyroOn ? "rotate.3d.fill" : "rotate.3d")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(gyroOn ? Theme.gold : .white)
                .frame(width: 44, height: 44)
                .glassPanel(cornerRadius: 22, tint: gyroOn ? Theme.gold : nil)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Text("Galáxia de nós · arraste para orbitar")
                .font(.App.caption)
                .foregroundColor(.white.opacity(0.7))

            Button {
                router.goStitching(session)
            } label: {
                Label("Montar panorama 360°", systemImage: "pano.fill")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(HoloButton(gradient: Theme.auroraColors, cornerRadius: Theme.R.md))
        }
    }

    private var cov: String {
        "\(Int((session.fractionComplete * 100).rounded()))%"
    }

    // MARK: - Gestures (deltas → scene, so orbiting feels inertial, not runaway)

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                scene.drag(by: CGSize(width: value.translation.width - lastDrag.width,
                                       height: value.translation.height - lastDrag.height))
                lastDrag = value.translation
            }
            .onEnded { _ in lastDrag = .zero }
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                let delta = lastMagnify == 0 ? scale : scale / lastMagnify
                scene.zoom(scale: delta)
                lastMagnify = scale
            }
            .onEnded { _ in lastMagnify = 1 }
    }
}

// MARK: - SceneKit host

private struct GalaxyHost: UIViewRepresentable {
    let scene: NodeWorldScene

    func makeUIView(context: Context) -> SCNView { scene.makeView() }
    func updateUIView(_ uiView: SCNView, context: Context) {}
}
