import SwiftUI

@main
struct Panorama360App: App {

    @StateObject private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(router)
                .preferredColorScheme(.dark)
                .statusBarHidden()
        }
    }
}
