import SwiftUI

/// Full-screen LiDAR 3D scanner. The live camera (the real room) fills the
/// screen while the mesh is collected; a coverage HUD climbs as areas are
/// mapped. Finish merges + saves the 3D mesh and jumps straight to the
/// walk-through. Mirrors the chrome/lifecycle of `LiveScanner3DView`. LiDAR only
/// — the entry point hides this route on unsupported devices.
struct RoomScanView: View {

    let projectID: UUID
    @StateObject private var vm: RoomScanViewModel
    @EnvironmentObject private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase
    @State private var didStart = false

    init(projectID: UUID) {
        self.projectID = projectID
        _vm = StateObject(wrappedValue: RoomScanViewModel(projectID: projectID))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            RoomScanSurface { arView in vm.attach(arView) }
                .ignoresSafeArea()

            ScanlineOverlay()
                .ignoresSafeArea()
                .opacity(0.5)
                .allowsHitTesting(false)

            // Centre reticle to show where the device is aiming.
            ZStack {
                Circle().stroke(Theme.cyan.opacity(0.7), lineWidth: 2).frame(width: 40, height: 40)
                Circle().fill(Theme.cyan).frame(width: 4, height: 4)
            }
            .allowsHitTesting(false)
            .shadow(color: Theme.cyan.opacity(0.4), radius: 8)

            VStack(spacing: 0) {
                topBar.padding(.horizontal, 20).padding(.top, 10)
                coverageMeter.padding(.horizontal, 20).padding(.top, 12)
                Spacer()
                statusPill
                Spacer()
                bottomChrome.padding(.horizontal, 20).padding(.bottom, 28)
            }
        }
        .tint(Theme.cyan)
        .onAppear { start() }
        .onChange(of: scenePhase) { phase in
            if phase == .background { vm.suspend() }
            else if phase == .active { vm.resume() }
        }
        .alert("Erro de scan", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { shown in if !shown { vm.dismissError() } }
        )) {
            Button("OK", role: .cancel) { vm.dismissError() }
        } message: { Text(vm.errorMessage ?? "") }
    }

    // MARK: - Lifecycle

    private func start() {
        guard !didStart else { return }
        didStart = true
        let router = self.router
        let pid = projectID
        vm.onComplete = { _ in router.goMeshWalk(pid) }
        vm.onCancel = { router.goProjectDetail(pid) }
        Task { vm.start() }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(spacing: 12) {
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
            Label("\(vm.meshAreaCount)", systemImage: "circle.hexagongrid.fill")
                .font(.App.hud)
            Divider().frame(height: 18).overlay(Color.white.opacity(0.3))
            Text("áreas 3D")
                .font(.App.micro)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14).padding(.vertical, 9)
        .glassPanel(cornerRadius: Theme.R.pill)
    }

    /// Colour-coverage meter — climbs as `MeshTexturizer` paints more vertices.
    /// Acts as the "scan points filling in" feedback the user asked for.
    private var coverageMeter: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Cobertura de cor")
                    .font(.App.micro)
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                Text("\(Int(vm.coverage * 100))%")
                    .font(.App.hud)
                    .foregroundColor(coverageColor)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    Capsule().fill(coverageColor)
                        .frame(width: max(0, geo.size.width * CGFloat(vm.coverage)))
                }
            }
            .frame(height: 8)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .glassPanel(cornerRadius: Theme.R.md)
        .animation(.easeOut(duration: 0.25), value: vm.coverage)
    }

    private var coverageColor: Color {
        if vm.coverage < 0.35 { return Theme.amber }
        if vm.coverage < 0.7 { return Theme.cyan }
        return Theme.mint
    }

    private var statusPill: some View {
        Label(vm.status, systemImage: "viewfinder.circle")
            .font(.App.caption)
            .foregroundColor(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .glassPanel(cornerRadius: Theme.R.pill, tint: Theme.cyan)
            .allowsHitTesting(false)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: vm.status)
    }

    private var bottomChrome: some View {
        Button {
            Haptics.shared.aligned()
            vm.finish()
        } label: {
            Label("Finalizar e ver em 3D", systemImage: "cube.transparent.fill")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(HoloButton(gradient: Theme.auroraColors, cornerRadius: Theme.R.md))
        .disabled(vm.meshAreaCount == 0)
    }
}
