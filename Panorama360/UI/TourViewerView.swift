import SwiftUI
import MetalKit

/// The multi-scene tour: an immersive Metal panorama you look around (drag /
/// pinch / gyro) with tappable hotspots that walk you between scenes, and an
/// edit mode to drop a hotspot at the centre of your current view and link it to
/// another scene. Scene-to-scene transitions fade through black. Chrome
/// auto-hides (except in edit mode) exactly like the single-panorama viewer.
struct TourViewerView: View {

    let projectID: UUID

    @StateObject private var vm: TourViewerViewModel
    @EnvironmentObject private var router: AppRouter

    @State private var lastDrag: CGSize = .zero
    @State private var chromeVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var gyroOn = false

    init(projectID: UUID) {
        self.projectID = projectID
        _vm = StateObject(wrappedValue: TourViewerViewModel(projectID: projectID))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let url = vm.initialURL() {
                MetalContainer(url: url,
                               onReady: { vm.attach(renderer: $0) },
                               onResize: { vm.updateAspect($0) })
                    .gesture(dragGesture)
                    .simultaneousGesture(magnifyGesture)
                    .simultaneousGesture(TapGesture().onEnded { poke() })
                    .ignoresSafeArea()
            } else {
                noSceneView
            }

            RadialGradient(colors: [.clear, .black.opacity(0.4)],
                           center: .center, startRadius: 0, endRadius: 520)
                .ignoresSafeArea().allowsHitTesting(false)

            // Hotspots above the sphere (transparent → drags fall through).
            HotspotOverlay(engine: vm.engine, vm: vm, editMode: vm.editMode,
                           onTap: { h in poke(); vm.transition(to: h.targetSceneID) },
                           onDelete: { vm.deleteHotspot(id: $0) })
                .ignoresSafeArea()
                .allowsHitTesting(vm.fadeOpacity < 0.5)

            if vm.editMode { editReticle }

            // Fade-through-black transition veil.
            Color.black.opacity(vm.fadeOpacity)
                .ignoresSafeArea().allowsHitTesting(false)

            // Loading spinner shown while the next scene decodes off the main
            // thread behind the veil (only during multi-scene transitions).
            if vm.isLoadingScene {
                VStack(spacing: 14) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(1.3)
                    Text("Carregando cena...")
                        .font(.App.caption)
                        .foregroundColor(.white.opacity(0.85))
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            chrome
                .opacity(chromeVisible ? 1 : 0)
                .animation(Theme.spring, value: chromeVisible)
        }
        .tint(Theme.cyan)
        .onAppear { poke() }
        .onDisappear { hideTask?.cancel(); vm.engine.stopGyro(); vm.detach() }
        .sheet(isPresented: $vm.showLinkSheet) { TourLinkSheet(vm: vm) }
        .alert("Cena indisponível", isPresented: $vm.unavailableNotice) {
            Button("OK", role: .cancel) {}
        } message: { Text("O panorama desta cena ainda não está pronto.") }
    }

    // MARK: - Chrome

    private var chrome: some View {
        VStack {
            topBar.padding(.horizontal, 20).padding(.top, 10)
            Spacer()
            bottomBar.padding(.horizontal, 20).padding(.bottom, 28)
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { router.goProjectDetail(projectID) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .glassPanel(cornerRadius: 22)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(vm.project?.title ?? "Tour")
                    .font(.App.hud).foregroundColor(.white).lineLimit(1)
                Text("\(vm.currentIndex + 1)/\(vm.project?.scenes.count ?? 0) · \(vm.currentScene?.title ?? "")")
                    .font(.App.micro).foregroundColor(.white.opacity(0.6)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { toggleGyro() } label: {
                Image(systemName: "gyroscope")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(gyroOn ? Theme.mint : .white)
                    .frame(width: 44, height: 44)
                    .glassPanel(cornerRadius: 22, tint: gyroOn ? Theme.mint : nil)
            }

            Button { toggleEdit() } label: {
                Image(systemName: vm.editMode ? "checkmark" : "wand.and.rays")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(vm.editMode ? Theme.mint : .white)
                    .frame(width: 44, height: 44)
                    .glassPanel(cornerRadius: 22, tint: vm.editMode ? Theme.mint : nil)
            }
        }
    }

    @ViewBuilder private var bottomBar: some View {
        if vm.editMode {
            editControls
        } else {
            HStack(spacing: 12) {
                Label("Toque nos pontos para navegar", systemImage: "hand.tap")
                    .font(.App.caption)
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                HStack(spacing: 8) {
                    navButton("chevron.left") { vm.previous() }
                    navButton("chevron.right") { vm.next() }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .glassPanel(cornerRadius: Theme.R.md)
        }
    }

    private func navButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .glassPanel(cornerRadius: 20)
        }
    }

    private var editControls: some View {
        VStack(spacing: 10) {
            Text("Mire na direção desejada e adicione o ponto")
                .font(.App.caption).foregroundColor(.white.opacity(0.7))
            Button {
                Haptics.shared.aligned()
                vm.beginAddHotspot()
            } label: {
                Label("Adicionar ponto aqui", systemImage: "plus.circle.fill")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(HoloButton(gradient: Theme.auroraColors, cornerRadius: Theme.R.md))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .glassPanel(cornerRadius: Theme.R.md, tint: Theme.mint)
    }

    private var editReticle: some View {
        ZStack {
            Circle().stroke(Theme.mint.opacity(0.8), lineWidth: 2).frame(width: 46, height: 46)
            Circle().fill(Theme.mint).frame(width: 5, height: 5)
        }
        .allowsHitTesting(false)
        .shadow(color: Theme.mint.opacity(0.5), radius: 8)
    }

    private var noSceneView: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 44)).foregroundColor(.white.opacity(0.5))
            Text("Nenhuma cena pronta neste tour.")
                .font(.App.caption).foregroundColor(.white.opacity(0.6))
        }
    }

    // MARK: - Chrome auto-hide / gyro

    private func poke() {
        chromeVisible = true
        hideTask?.cancel()
        if vm.editMode { return }
        hideTask = Task { try? await Task.sleep(nanoseconds: 3_500_000_000)
            if !Task.isCancelled { chromeVisible = false } }
    }

    private func toggleGyro() {
        poke()
        gyroOn.toggle()
        if gyroOn { vm.engine.startGyro() } else { vm.engine.stopGyro() }
    }

    private func toggleEdit() {
        vm.editMode.toggle()
        if vm.editMode { gyroOn = false; vm.engine.stopGyro() }
        chromeVisible = true
        poke()
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                poke()
                let delta = CGSize(width: value.translation.width - lastDrag.width,
                                   height: value.translation.height - lastDrag.height)
                vm.engine.drag(by: delta)
                lastDrag = value.translation
            }
            .onEnded { _ in lastDrag = .zero }
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in poke(); vm.engine.zoom(scale: value) }
    }
}
