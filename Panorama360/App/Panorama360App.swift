import SwiftUI

@main
struct Panorama360App: App {

    @StateObject private var router = AppRouter()

    init() {
        // Catch ObjC exceptions (most AVFoundation/camera crashes) and persist
        // the reason so the next launch can display it — there's no Mac console
        // attached when sideloading from Windows.
        CrashReporter.install()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(router)
                .preferredColorScheme(.dark)
                .statusBarHidden()
                .tint(Theme.cyan)
        }
    }
}
