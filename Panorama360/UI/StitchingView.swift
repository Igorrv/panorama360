import SwiftUI

/// Runs the panorama stitcher and shows a stage-by-stage pipeline.
struct StitchingView: View {

    let session: PanoramaSession

    @StateObject private var vm = StitchingViewModel()
    @EnvironmentObject private var router: AppRouter
    @State private var didStart = false

    var body: some View {
        ZStack {
            backgroundGradient
            VStack(spacing: 36) {
                Spacer()

                CircularProgressView(progress: vm.progress)
                    .frame(width: 180, height: 180)

                Text("Stitching Panorama")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                stageList
                    .padding(.horizontal, 32)

                Spacer()
            }
            .padding(.bottom, 40)
        }
        .onAppear {
            guard !didStart else { return }
            didStart = true
            vm.onComplete = { router.goViewer($0) }
            vm.run(session: session)
        }
        .alert("Stitching failed",
               isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { shown in if !shown { vm.dismissError() } }
               )) {
            Button("Back to capture", role: .cancel) {
                vm.dismissError()
                router.goCapture()
            }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // MARK: - Subviews

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color(red: 0.04, green: 0.05, blue: 0.10),
                     Color.black],
            startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }

    private var stageList: some View {
        VStack(spacing: 10) {
            ForEach(StitchStage.allCases, id: \.self) { stage in
                stageRow(stage)
            }
        }
        .padding(18)
        .frame(maxWidth: 360)
        .glassPanel(cornerRadius: 20)
    }

    private func stageRow(_ stage: StitchStage) -> some View {
        let isCurrent = (stage == vm.stage && !vm.didFinish)
        let isDone = vm.didFinish || stage.order < vm.stage.order

        return HStack(spacing: 14) {
            ZStack {
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.green)
                } else if isCurrent {
                    ProgressView()
                        .tint(.white)
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 6, height: 6)
                }
            }
            .frame(width: 22, height: 22)

            Text(stage.rawValue)
                .font(.system(size: 14, weight: isCurrent ? .semibold : .regular, design: .rounded))
                .foregroundStyle(isDone || isCurrent ? .white : .white.opacity(0.4))

            Spacer()
        }
        .animation(.easeInOut(duration: 0.25), value: vm.stage)
    }
}
