import SwiftUI

/// Runs the panorama stitcher and shows a stage-by-stage pipeline over the
/// holographic background. Each stage row carries its own SF Symbol; the active
/// stage glows cyan, completed stages show a mint check.
struct StitchingView: View {

    let session: PanoramaSession

    @StateObject private var vm = StitchingViewModel()
    @EnvironmentObject private var router: AppRouter
    @State private var didStart = false

    var body: some View {
        ZStack {
            HoloBackground()
            VStack(spacing: 32) {
                Spacer()

                CircularProgressView(progress: vm.progress, centerSymbol: Self.symbol(for: vm.stage))
                    .frame(width: 184, height: 184)

                Text("Montando o panorama 360°")
                    .font(.App.headline)
                    .foregroundColor(.white)
                    .glow(Theme.cyan, radius: 10)

                stageList
                    .padding(.horizontal, 32)

                Spacer()
            }
            .padding(.bottom, 40)
        }
        .onAppear {
            guard !didStart else { return }
            didStart = true
            vm.onComplete = { url in
                // Project ("add scene") mode: commit the stitched session as a
                // new scene and return to the project. Standalone: open viewer.
                if router.captureContext != nil {
                    router.commitAddScene(session: session)
                } else {
                    router.goViewer(url)
                }
            }
            vm.run(session: session)
        }
        .alert("Falha ao montar",
               isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { shown in if !shown { vm.dismissError() } }
               )) {
            Button("Voltar à captura", role: .cancel) {
                vm.dismissError()
                router.goCapture()
            }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // MARK: - Stage list

    private var stageList: some View {
        VStack(spacing: 10) {
            ForEach(StitchStage.allCases, id: \.self) { stage in
                stageRow(stage)
            }
        }
        .padding(18)
        .frame(maxWidth: 360)
        .glassPanel(cornerRadius: Theme.R.lg, tint: Theme.cyan)
    }

    private func stageRow(_ stage: StitchStage) -> some View {
        let isCurrent = (stage == vm.stage && !vm.didFinish)
        let isDone = vm.didFinish || stage.order < vm.stage.order

        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill((isCurrent ? Theme.cyan : Color.white).opacity(isCurrent ? 0.16 : 0.08))
                    .frame(width: 30, height: 30)
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Theme.mint)
                } else {
                    Image(systemName: Self.symbol(for: stage))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isCurrent ? Theme.cyan : .white.opacity(0.35))
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .glow(Theme.cyan.opacity(isCurrent ? 1 : 0), radius: isCurrent ? 8 : 0)

            Text(stage.rawValue)
                .font(.system(size: 14, weight: isCurrent ? .semibold : .regular, design: .rounded))
                .foregroundColor(isDone || isCurrent ? .white : .white.opacity(0.4))

            Spacer()
        }
        .animation(Theme.spring, value: vm.stage)
    }

    // MARK: - Stage → SF Symbol

    private static func symbol(for stage: StitchStage) -> String {
        switch stage {
        case .loading:      return "photo.stack"
        case .undistorting: return "camera.aperture"
        case .exposure:     return "sun.max"
        case .projecting:   return "globe"
        case .finalizing:   return "sparkles"
        }
    }
}
