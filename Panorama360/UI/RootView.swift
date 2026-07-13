import SwiftUI

/// Switches between capture → stitching → viewer based on `AppRouter`.
struct RootView: View {

    @EnvironmentObject private var router: AppRouter

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch router.route {
            case .onboarding:
                OnboardingView()
                    .transition(.opacity)
            case .capture:
                CaptureView(distribution: router.tutorialActive ? .tutorial : .default)
                    .id(router.captureGeneration)
                    .transition(.opacity)
            case .stitching(let session):
                StitchingView(session: session)
                    .transition(.opacity)
            case .viewer(let url):
                PanoramaViewerView(url: url)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: routeTag(router.route))
    }

    private func routeTag(_ route: AppRouter.Route) -> String {
        switch route {
        case .onboarding: return "onboarding"
        case .capture: return "capture"
        case .stitching: return "stitching"
        case .viewer: return "viewer"
        }
    }
}
