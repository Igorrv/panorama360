import SwiftUI

/// Switches between onboarding → capture → stitching → viewer based on
/// `AppRouter`. Each route carries a directional transition so navigation feels
/// cinematic: stitching "rises" from the bottom, the viewer "resolves" with a
/// scale-in, the camera/onboarding hand off with a clean fade.
struct RootView: View {

    @EnvironmentObject private var router: AppRouter

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch router.route {
            case .onboarding:
                OnboardingView()
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96)),
                        removal: .opacity))
            case .library:
                LibraryView()
                    .transition(.opacity)
            case .capture:
                if router.tutorialActive {
                    CaptureView(mode: .fixed(.tutorial))
                        .id(router.captureGeneration)
                        .transition(.opacity)
                } else {
                    // Live 3D Projection Scanner (real capture): pure-black
                    // wireframe grid that fills in photo-by-photo as nodes lock.
                    LiveScanner3DView()
                        .id(router.captureGeneration)
                        .transition(.opacity)
                }
            case .stitching(let session):
                StitchingView(session: session)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity))
            case .world(let session):
                NodeGalaxyView(session: session)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.92).combined(with: .opacity),
                        removal: .opacity))
            case .projectDetail(let id):
                ProjectDetailView(projectID: id)
                    .id(id)
                    .transition(.opacity)
            case .tourViewer(let id):
                TourViewerView(projectID: id)
                    .id(id)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.92).combined(with: .opacity),
                        removal: .opacity))
            case .roomScan(let id):
                RoomScanView(projectID: id)
                    .id(id)
                    .transition(.opacity)
            case .meshWalk(let id):
                MeshWalkView(projectID: id)
                    .id(id)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.92).combined(with: .opacity),
                        removal: .opacity))
            case .viewer(let url):
                PanoramaViewerView(url: url)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                        removal: .opacity))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: routeTag(router.route))
    }

    private func routeTag(_ route: AppRouter.Route) -> String {
        switch route {
        case .onboarding:    return "onboarding"
        case .library:       return "library"
        case .capture:       return "capture"
        case .world:         return "world"
        case .projectDetail: return "projectDetail"
        case .tourViewer:    return "tourViewer"
        case .roomScan:      return "roomScan"
        case .meshWalk:      return "meshWalk"
        case .stitching:     return "stitching"
        case .viewer:        return "viewer"
        }
    }
}
