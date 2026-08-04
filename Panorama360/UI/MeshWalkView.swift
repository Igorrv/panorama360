import SwiftUI
import RealityKit

/// The 3D walk-through viewer: a non-AR `ARView` renders the saved mesh; drag
/// anywhere to look (yaw/pitch), the joystick moves (free-fly, fixed height).
/// Chrome mirrors the immersive screens (back/reset top, hint + joystick
/// bottom). Empty chrome space passes drags through to the look gesture.
struct MeshWalkView: View {

    let projectID: UUID
    @StateObject private var vm: WalkViewModel
    @EnvironmentObject private var router: AppRouter
    @State private var lastDrag: CGSize = .zero

    init(projectID: UUID) {
        self.projectID = projectID
        _vm = StateObject(wrappedValue: WalkViewModel(projectID: projectID))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            WalkSurface { arView in vm.attach(arView) }
                .ignoresSafeArea()
                .gesture(lookGesture)

            VStack(spacing: 0) {
                topBar.padding(.horizontal, 20).padding(.top, 10)
                Spacer()
                HStack(alignment: .bottom) {
                    hintPill
                    Spacer()
                    WalkJoystick { vm.setMove($0) }
                }
                .padding(.horizontal, 20).padding(.bottom, 28)
            }
        }
        .tint(Theme.cyan)
        .onDisappear { vm.detach() }
        .alert("Erro no 3D", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { shown in if !shown { vm.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { vm.errorMessage = nil; router.goProjectDetail(projectID) }
        } message: { Text(vm.errorMessage ?? "") }
    }

    // MARK: - Look gesture

    private var lookGesture: some Gesture {
        DragGesture()
            .onChanged { v in
                let d = CGSize(width: v.translation.width - lastDrag.width,
                               height: v.translation.height - lastDrag.height)
                lastDrag = v.translation
                // Drag right ⇒ look right; drag up ⇒ look up.
                vm.look(deltaYaw: -Float(d.width) * 0.005,
                        deltaPitch: -Float(d.height) * 0.005)
            }
            .onEnded { _ in lastDrag = .zero }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { router.goProjectDetail(projectID) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .glassPanel(cornerRadius: 22)
            }
            Text("Caminhada 3D")
                .font(.App.hud).foregroundColor(.white)
            Spacer()
            Button { Haptics.shared.aligned(); vm.resetView() } label: {
                Image(systemName: "arrow.uturn.left.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .glassPanel(cornerRadius: 22)
            }
        }
    }

    private var hintPill: some View {
        Label(vm.status, systemImage: "info.circle")
            .font(.App.caption)
            .foregroundColor(.white)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .glassPanel(cornerRadius: Theme.R.pill)
            .allowsHitTesting(false)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: vm.status)
    }
}

/// Non-AR `ARView` surface for the walk-through viewer (no live session).
private struct WalkSurface: UIViewRepresentable {
    let onReady: (ARView) -> Void

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.backgroundColor = .black
        onReady(view)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
