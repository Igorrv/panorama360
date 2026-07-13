import SwiftUI
import UIKit

/// The main capture screen: live camera, floating guide points, central reticle,
/// progress bar, stability indicator and a cancel button.
struct CaptureView: View {

    @StateObject private var vm: CaptureViewModel
    @EnvironmentObject private var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase
    @State private var didStart = false
    /// Persisted crash note from the previous launch (nil if none). Shown as a
    /// banner so the cause of a silent crash is recoverable without a Mac console.
    @State private var lastCrash: String? = CrashReporter.lastCrash()
    @State private var didCopyCrash = false

    init(distribution: SphereDistribution = .default) {
        _vm = StateObject(wrappedValue: CaptureViewModel(distribution: distribution))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                CameraPreview(session: vm.camera.session, orientation: .portrait)
                    .ignoresSafeArea()

                CaptureOverlay(guide: vm.guide)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                ReticleView(state: vm.reticle,
                            stability: vm.stabilityScore,
                            pulse: vm.guide.capturePulse)

                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    ProgressView360(fraction: vm.fractionComplete,
                                    captured: vm.capturedCount,
                                    total: vm.totalPoints,
                                    eta: vm.etaSeconds,
                                    stability: vm.stabilityScore)
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
            .onAppear {
                guard !didStart else { return }
                didStart = true
                vm.setViewport(geo.size)
                vm.onComplete = { router.goStitching($0) }
                // From the tutorial, cancel returns to onboarding; otherwise a fresh capture.
                vm.onCancel = {
                    if router.tutorialActive { router.goOnboarding() } else { router.goCapture() }
                }
                Task { await vm.start() }
            }
            // Stop the camera the instant the app is backgrounded — iOS kills
            // apps that keep capturing while suspended (a major "app just closes"
            // cause). Restart on return.
            .onChange(of: scenePhase) { phase in
                if phase == .background { vm.suspend() }
                else if phase == .active { vm.resume() }
            }
            .alert("Capture Error", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { shown in if !shown { vm.dismissError() } }
            )) {
                Button("OK", role: .cancel) { vm.dismissError() }
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
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
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
        }
        .shadow(color: .black.opacity(0.4), radius: 6)
    }

    /// Manual escape hatch: build the 360° view now with the photos taken so far
    /// (appears after the first capture). Lets the user reach the viewer even if
    /// the auto-gate is slow.
    private var finishButton: some View {
        Button {
            vm.finishCapture()
        } label: {
            Label("Finish & build 360°", systemImage: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.blue.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .blue.opacity(0.4), radius: 10)
        }
    }

    // MARK: - Crash banner

    /// Shows the persisted reason the previous launch crashed, with Copy (to
    /// paste into a message to the dev / a bug report) and Dismiss. The text is
    /// scrollable because the call stack can be long.
    private func crashBanner(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("Previous launch crashed")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
            }
            ScrollView {
                Text(text)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)

            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = text
                    didCopyCrash = true
                } label: {
                    Label(didCopyCrash ? "Copied" : "Copy",
                          systemImage: didCopyCrash ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(.white)

                Button {
                    CrashReporter.clear()
                    lastCrash = nil
                } label: {
                    Label("Dismiss", systemImage: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
        }
        .padding(14)
        .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.2), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 10)
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
                        .fill(barColor(for: i))
                        .frame(width: 8, height: 14 + CGFloat(i) * 4)
                }
            }
            Text("STABILITY")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1))
        .animation(.easeOut(duration: 0.15), value: score)
    }

    private func barColor(for index: Int) -> Color {
        let activeCount = Int(score * 5)
        return index < activeCount ? .green : .white.opacity(0.18)
    }
}
