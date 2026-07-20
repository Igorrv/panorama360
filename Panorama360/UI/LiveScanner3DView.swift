import SwiftUI

/// The immersive "build-the-space" scanner. The **whole screen IS the live 360°
/// globe**: every photo you take is projected onto the sphere at the direction
/// you captured, feathered-blended into a growing environment you look around
/// inside by rotating the phone — the Teleport 360 experience. It starts pure
/// black, then the space materialises photo by photo as you scan a section.
///
/// A floating target grid + precision reticle guide where to aim. Capture fires
/// automatically when you hold still on a target (the sharpness gate) AND via a
/// manual shutter, so you can deliberately scan a section even in low light. The
/// camera runs underneath (silent capture + sharpness gate) but stays hidden —
/// the built space is the only thing on screen.
///
/// Reuses `CaptureViewModel` for camera / motion / session / the live-globe
/// reconstruction (each capture is pushed to `LiveReconstructionManager`, which
/// renders the growing equirect on the inside of the sphere).
struct LiveScanner3DView: View {

    @StateObject private var vm: CaptureViewModel
    @EnvironmentObject private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase
    @State private var didStart = false

    /// Default route is the full-sphere real-estate preset (ceiling + floor
    /// included) so the stitched panorama renders the whole environment.
    init(mode: GuideMode = .fixed(.realEstate)) {
        _vm = StateObject(wrappedValue: CaptureViewModel(mode: mode))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                // The immersive globe — the space you build. Full screen.
                LiveMeshPreview { renderer, manager in
                    vm.attachLiveGlobe(renderer: renderer, manager: manager)
                }
                .ignoresSafeArea()

                // Floating target nodes — aim guidance over the globe.
                CaptureOverlay(guide: vm.guide)
                    .ignoresSafeArea()
                    .opacity(0.9)

                // Scanner motif: a slow sweep over the built space.
                ScanlineOverlay()
                    .ignoresSafeArea()
                    .opacity(0.6)

                // Precision reticle + capture-confidence arc, centred on aim.
                ReticleView(state: vm.reticle,
                            confidence: Double(vm.captureConfidence),
                            pulse: vm.guide.capturePulse)

                // Why capture isn't firing right now — surfaced from the gate.
                if let hint = vm.statusHint {
                    Label(hint, systemImage: "scope")
                        .font(.App.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .glassPanel(cornerRadius: Theme.R.pill, tint: Theme.amber)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .offset(y: 104)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: hint)
                }

                // Pole prompt — "Aponte para o teto/chão" when the nearest
                // un-captured target is near the zenith/nadir (full-sphere scans).
                if let pole = vm.poleHint {
                    Label(pole, systemImage: "arrow.up.arrow.down.circle")
                        .font(.App.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .glassPanel(cornerRadius: Theme.R.pill, tint: Theme.mint)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .offset(y: 150)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: pole)
                }

                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                    Spacer()
                    bottomChrome
                        .padding(.horizontal, 20)
                        .padding(.bottom, 28)
                }
                .animation(.easeInOut(duration: 0.25), value: vm.canFinish)
            }
            .tint(Theme.cyan)
            .onAppear { start(in: geo.size) }
            .onChange(of: scenePhase) { phase in
                if phase == .background { vm.suspend() }
                else if phase == .active { vm.resume() }
            }
            .alert("Erro de captura", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { shown in if !shown { vm.dismissError() } }
            )) {
                Button("OK", role: .cancel) { vm.dismissError() }
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
    }

    // MARK: - Lifecycle

    private func start(in size: CGSize) {
        guard !didStart else { return }
        didStart = true
        vm.setViewport(size)
        // Capture a stable reference — the closure must not capture the struct
        // snapshot of `self`.
        let router = self.router
        // In project ("add scene") mode a finished capture goes straight to
        // stitching so it becomes a scene; standalone captures land in the node
        // galaxy as before.
        vm.onComplete = { session in
            if router.captureContext != nil {
                router.goStitching(session)
            } else {
                router.goWorld(session)
            }
        }
        vm.onCancel = {
            if router.captureContext != nil {
                router.cancelAddScene()
            } else {
                router.goCapture()
            }
        }
        Task { await vm.start() }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(spacing: 14) {
            Button { vm.cancel() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .glassPanel(cornerRadius: 22)
            }

            Spacer()

            coveragePill
        }
    }

    private var coveragePill: some View {
        HStack(spacing: 8) {
            Label("\(vm.capturedCount)/\(vm.totalPoints)", systemImage: "circle.hexagongrid.fill")
                .font(.App.hud)
            Divider().frame(height: 18).overlay(Color.white.opacity(0.3))
            Text("\(Int((vm.fractionComplete * 100).rounded()))%")
                .font(.App.hud)
            if vm.includesPoles {
                Divider().frame(height: 18).overlay(Color.white.opacity(0.3))
                poleGlyph("arrow.up.circle.fill", active: vm.ceilingCaptured)
                poleGlyph("arrow.down.circle.fill", active: vm.floorCaptured)
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14).padding(.vertical, 9)
        .glassPanel(cornerRadius: Theme.R.pill)
    }

    /// Teto/chão coverage glyph — mint when that pole shot is captured, dim otherwise.
    private func poleGlyph(_ name: String, active: Bool) -> some View {
        Image(systemName: name)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(active ? Theme.mint : .white.opacity(0.3))
    }

    /// Manual shutter (always available — scan a section on demand) plus the
    /// finish button once at least one photo exists.
    private var bottomChrome: some View {
        VStack(spacing: 16) {
            if vm.canFinish {
                finishButton
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            shutterButton
        }
    }

    private var shutterButton: some View {
        Button {
            Haptics.shared.aligned()
            Task { await vm.captureNow() }
        } label: {
            ZStack {
                Circle()
                    .stroke(.white.opacity(vm.isCapturing ? 0.3 : 0.75), lineWidth: 5)
                    .frame(width: 76, height: 76)
                Circle()
                    .fill(Theme.cyan)
                    .frame(width: 62, height: 62)
                    .scaleEffect(vm.isCapturing ? 0.82 : 1)
                    .shadow(color: Theme.cyan.opacity(0.55), radius: 10)
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: vm.isCapturing)
        }
        .disabled(vm.isCapturing)
    }

    private var finishButton: some View {
        Button { vm.finishCapture() } label: {
            Label("Montar panorama 360°", systemImage: "pano.fill")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(HoloButton(gradient: Theme.auroraColors, cornerRadius: Theme.R.md))
    }
}
