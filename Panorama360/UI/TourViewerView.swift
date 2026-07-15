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

    // Link-authoring sheet state (seeded from the draft on appear).
    @State private var linkTarget: TourScene?
    @State private var linkLabel = ""
    @State private var linkIcon = "arrow.right.circle.fill"

    private static let icons: [(String, String)] = [
        ("arrow.right.circle.fill", "Passagem"),
        ("door.right.hand.open", "Porta"),
        ("arrow.up.circle.fill", "Subir"),
        ("arrow.down.circle.fill", "Descer"),
        ("info.circle.fill", "Info")
    ]

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

            chrome
                .opacity(chromeVisible ? 1 : 0)
                .animation(Theme.spring, value: chromeVisible)
        }
        .tint(Theme.cyan)
        .onAppear { poke() }
        .onDisappear { hideTask?.cancel(); vm.engine.stopGyro() }
        .sheet(isPresented: $vm.showLinkSheet) { linkSheet }
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

    // MARK: - Link-authoring sheet

    private var linkSheet: some View {
        VStack(spacing: 18) {
            Text("Novo ponto de passagem")
                .font(.App.headline).foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            if vm.otherScenes().isEmpty {
                Label("Adicione outra cena a este projeto antes de criar um link.",
                      systemImage: "info.circle")
                    .font(.App.caption).foregroundColor(.white.opacity(0.7))
            } else {
                targetPicker
                iconRow
                TextField("Rótulo (ex.: Cozinha)", text: $linkLabel)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color.white.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: Theme.R.md))
                    .foregroundColor(.white)
            }

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Button("Cancelar", role: .cancel) { vm.cancelHotspot() }
                    .frame(maxWidth: .infinity).padding(.vertical, 4)
                    .glassPanel(cornerRadius: Theme.R.md)
                Button {
                    guard let t = linkTarget else { return }
                    vm.commitHotspot(targetSceneID: t.id,
                                     label: linkLabel.trimmingCharacters(in: .whitespaces).isEmpty
                                            ? t.title : linkLabel,
                                     icon: linkIcon)
                } label: {
                    Text("Criar link").frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(HoloButton(gradient: Theme.auroraColors, cornerRadius: Theme.R.md))
                .disabled(linkTarget == nil)
            }
        }
        .padding(22)
        .background(Color.black.ignoresSafeArea())
        .onAppear { seedLinkSheet() }
    }

    private var targetPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cena de destino").font(.App.micro).foregroundColor(.white.opacity(0.6))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.otherScenes()) { scene in
                        let sel = linkTarget?.id == scene.id
                        Button { linkTarget = scene } label: {
                            Text(scene.title).font(.App.caption)
                                .foregroundColor(sel ? .black : .white)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(sel ? AnyShapeStyle(Theme.mint) : AnyShapeStyle(Color.white.opacity(0.1)),
                                            in: Capsule())
                        }
                    }
                }
            }
        }
    }

    private var iconRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Self.icons, id: \.0) { icon, label in
                    let sel = linkIcon == icon
                    Button { linkIcon = icon } label: {
                        VStack(spacing: 4) {
                            Image(systemName: icon).font(.system(size: 20))
                            Text(label).font(.system(size: 9))
                        }
                        .foregroundColor(sel ? .black : .white)
                        .frame(width: 58, height: 50)
                        .background(sel ? AnyShapeStyle(Theme.mint) : AnyShapeStyle(Color.white.opacity(0.08)),
                                    in: RoundedRectangle(cornerRadius: Theme.R.sm))
                    }
                }
            }
        }
    }

    private func seedLinkSheet() {
        if linkTarget == nil { linkTarget = vm.otherScenes().first }
        linkLabel = vm.draftHotspot?.label ?? ""
        if let icon = vm.draftHotspot?.iconName { linkIcon = icon }
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
