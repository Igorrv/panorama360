import SwiftUI

/// The main capture screen: live camera, floating guide points, central reticle,
/// progress bar, stability indicator and a cancel button.
struct CaptureView: View {

    @StateObject private var vm: CaptureViewModel
    @EnvironmentObject private var router: AppRouter
    @State private var didStart = false

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
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
            .onAppear {
                guard !didStart else { return }
                didStart = true
                vm.setViewport(geo.size)
                vm.onComplete = { router.goStitching($0) }
                vm.onCancel = { router.goCapture() }
                Task { await vm.start() }
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
