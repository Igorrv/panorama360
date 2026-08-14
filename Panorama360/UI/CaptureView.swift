import SwiftUI
import UIKit

/// The main capture screen: live camera under a scanner overlay, floating guide
/// points, the precision reticle, the live 360° globe (PiP) framed by a rotating
/// HUD ring, progress, and a cancel button.
struct CaptureView: View {

    @StateObject private var vm: CaptureViewModel
    @EnvironmentObject private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase
    @State private var didStart = false
    /// Persisted crash note from the previous launch (nil if none). Shown as a
    /// banner so the cause of a silent crash is recoverable without a Mac console.
    @State private var lastCrash: String? = CrashReporter.lastCrash()
    @State private var didCopyCrash = false

    init(mode: GuideMode = .dynamic) {
        _vm = StateObject(wrappedValue: CaptureViewModel(mode: mode))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                CameraPreview(session: vm.camera.session, orientation: .portrait)
                    .ignoresSafeArea()

                // Dark Scanner: the capture session keeps running underneath
                // (so photos + the sharpness gate still work), but the user sees
                // pure #000000 with floating holographic nodes — no live feed.
                Color.black.ignoresSafeArea()

                CaptureOverlay(guide: vm.guide)
                    .ignoresSafeArea()

                // Scanner overlay: sweeping line + corner brackets over the camera.
                ScanlineOverlay()
                    .ignoresSafeArea()
                    .opacity(0.9)

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
                        .offset(y: 96)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: hint)
                }

                // Live, growing 360° globe (picture-in-picture). Fills in as you
                // capture and rotates with the phone.
                liveGlobePiP

                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    ProgressView360(fraction: vm.fractionComplete,
                                    captured: vm.capturedCount,
                                    total: vm.totalPoints,
                                    eta: vm.etaSeconds,
                                    stability: vm.stabilityScore,
                                    coverageFraction: vm.usesCoverage ? vm.coverageFraction : nil)
                    if vm.canFinish {
                        finishButton
                            .padding(.top, 14)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 28)
                .animation(.easeInOut(duration: 0.25), value: vm.canFinish)

                if let lastCrash {
                    crashBanner(lastCrash)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .allowsHitTesting(true)
                }
            }
            .tint(Theme.cyan)
            .onAppear {
                guard !didStart else { return }
                didStart = true
                vm.setViewport(geo.size)
                // Finish always runs the stitcher so the tutorial ends in a real
                // navigable 360° photo; the viewer's back button then clears
                // onboarding. (Was `goWorld` — the legacy node galaxy, not a panorama.)
                vm.onComplete = { router.goStitching($0) }
                // From the tutorial, cancel returns to onboarding; otherwise a fresh capture.
                vm.onCancel = {
                    if router.tutorialActive { router.goOnboarding() } else { router.goCapture() }
                }
                Task { await vm.start() }
            }
            // Stop the camera the instant the app is backgrounded — iOS kills
            // apps that keep capturing while suspended. Restart on return.
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

    // MARK: - Live globe PiP

    /// The live globe on a dark disc, wrapped by a rotating tick ring whose arc
    /// fills with sphere coverage. A glass badge reports the %.
    private var liveGlobePiP: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Theme.ink.opacity(0.55))
                    .frame(width: 132, height: 132)
                LiveMeshPreview { renderer, manager in
                    vm.attachLiveGlobe(renderer: renderer, manager: manager)
                }
                .frame(width: 116, height: 116)
                .clipShape(Circle())
                HUDRing(tickCount: 40, rotationSeconds: 20,
                        fill: vm.fractionComplete, color: Theme.cyan)
                    .frame(width: 132, height: 132)
            }
            .frame(width: 132, height: 132)
            .shadow(color: .black.opacity(0.5), radius: 10)

            Text("GLOBO \(Int((vm.fractionComplete * 100).rounded()))%")
                .font(.App.micro)
                .tracking(1)
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .glassPanel(cornerRadius: Theme.R.pill)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, 64)
        .padding(.trailing, 20)
        .allowsHitTesting(false)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .top, spacing: 16) {
            StabilityIndicator(score: vm.stabilityScore)
            Spacer()
            cancelButton
        }
    }

    private var cancelButton: some View {
        Button {
            vm.cancel()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .glassPanel(cornerRadius: 22)
        }
        .shadow(color: .black.opacity(0.4), radius: 6)
    }

    /// Manual escape hatch: build the 360° view now with the photos taken so far.
    private var finishButton: some View {
        Button {
            vm.finishCapture()
        } label: {
            Label("Finalizar e montar 360°", systemImage: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
        }
        .buttonStyle(HoloButton(gradient: Theme.successColors, cornerRadius: Theme.R.md))
    }

    // MARK: - Crash banner

    /// Shows the persisted reason the previous launch crashed. If the report is
    /// empty, the app was almost certainly killed by iOS (memory / watchdog) —
    /// SIGKILL cannot be caught — so we say so plainly.
    private func crashBanner(_ text: String) -> some View {
        let isEmpty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Theme.amber)
                Text("O app fechou na última vez")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
            }

            ScrollView {
                if isEmpty {
                    Text("O app foi fechado pelo iOS sem deixar motivo — quase sempre é um encerramento por memória (SIGKILL não pode ser capturado).\n\n• Feche outros apps e tente de novo.\n• O detalhe real está em Ajustes → Privacidade e Segurança → Análises e Melhorias → Dados de Análise → Panorama360 (.ips).")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(text)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxHeight: 170)

            HStack(spacing: 10) {
                if !isEmpty {
                    Button {
                        UIPasteboard.general.string = text
                        Haptics.shared.captured()
                        didCopyCrash = true
                    } label: {
                        Label(didCopyCrash ? "Copiado ✓" : "Copiar",
                              systemImage: didCopyCrash ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }

                Button {
                    CrashReporter.clear()
                    lastCrash = nil
                } label: {
                    Label("Fechar", systemImage: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
        }
        .padding(14)
        .glassPanel(cornerRadius: Theme.R.lg, tint: Color(red: 1.0, green: 0.34, blue: 0.34))
    }
}

// MARK: - Stability indicator

private struct StabilityIndicator: View {
    let score: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(0..<5) { i in
                    Capsule()
                        .fill(barStyle(for: i))
                        .frame(width: 7, height: 12 + CGFloat(i) * 4)
                }
            }
            Text("ESTABILIDADE")
                .font(.App.micro)
                .tracking(1.5)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(12)
        .glassPanel(cornerRadius: Theme.R.md)
        .animation(.easeOut(duration: 0.15), value: score)
    }

    private func barStyle(for index: Int) -> AnyShapeStyle {
        index < Int(score * 5)
            ? AnyShapeStyle(Theme.progress)
            : AnyShapeStyle(Color.white.opacity(0.18))
    }
}
