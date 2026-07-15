import SwiftUI
import MetalKit

/// The 360° viewer screen: a Metal sphere you orbit by drag / pinch / gyro.
/// Holographic chrome auto-hides after a few seconds idle and reappears on
/// interaction; a heading compass + FOV pill track the live view.
struct PanoramaViewerView: View {

    let url: URL

    @StateObject private var vm = ViewerViewModel()
    @EnvironmentObject private var router: AppRouter

    @State private var lastDrag: CGSize = .zero
    @State private var chromeVisible = true
    @State private var hideTask: Task<Void, Never>?
    /// Local mirror of the gyro state — `engine.gyroEnabled` isn't `@Published`
    /// (and ViewerEngine is a locked logic file), so we track it here for the
    /// button tint and toggle in lockstep.
    @State private var gyroOn = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            MetalContainer(url: url,
                           onReady: { renderer in vm.attach(renderer: renderer) },
                           onResize: { vm.engine.updateAspect($0) })
                .gesture(dragGesture)
                .simultaneousGesture(magnifyGesture)
                .simultaneousGesture(TapGesture().onEnded { poke() })
                .ignoresSafeArea()

            // Vignette for depth.
            RadialGradient(colors: [.clear, .black.opacity(0.45)],
                           center: .center, startRadius: 0, endRadius: 500)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Viewport corner brackets.
            ViewerBrackets()
                .stroke(Theme.cyan.opacity(0.35),
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Auto-hiding chrome.
            VStack {
                topBar
                Spacer()
                HeadingCompass(engine: vm.engine)
                Spacer()
                bottomBar
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 28)
            .opacity(chromeVisible ? 1 : 0)
            .animation(Theme.spring, value: chromeVisible)
        }
        .onAppear { poke() }
        .onDisappear { hideTask?.cancel() }
    }

    // MARK: - Chrome auto-hide

    private func poke() {
        chromeVisible = true
        hideTask?.cancel()
        hideTask = Task { try? await Task.sleep(nanoseconds: 3_500_000_000)
            if !Task.isCancelled { chromeVisible = false } }
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                poke()
                let delta = CGSize(width: value.translation.width - lastDrag.width,
                                   height: value.translation.height - lastDrag.height)
                vm.engine.drag(by: delta)
                lastDrag = value.translation
            }
            .onEnded { _ in lastDrag = .zero }
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in poke(); vm.engine.zoom(scale: value) }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button {
                // Reaching the viewer = a panorama was built; that unlocks the
                // full app for future launches and clears the tutorial flag.
                router.completeOnboarding()
                router.goLibrary()
            } label: {
                Group {
                    if router.tutorialActive {
                        Label("Concluir", systemImage: "checkmark")
                            .font(.system(size: 15, weight: .semibold))
                            .padding(.horizontal, 14).frame(height: 44)
                    } else {
                        Label("Novo", systemImage: "chevron.left")
                            .labelStyle(.iconOnly)
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                }
                .foregroundColor(.white)
                .glassPanel(cornerRadius: 22, tint: router.tutorialActive ? Theme.mint : nil)
            }

            Spacer()

            Text("360°")
                .font(.App.micro)
                .tracking(2)
                .foregroundColor(Theme.cyan)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .glassPanel(cornerRadius: Theme.R.pill)

            Spacer()

            Button {
                poke(); gyroOn.toggle(); vm.toggleGyro()
            } label: {
                Image(systemName: "gyroscope")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(gyroOn ? Theme.mint : .white)
                    .frame(width: 44, height: 44)
                    .glassPanel(cornerRadius: 22, tint: gyroOn ? Theme.mint : nil)
            }
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 18) {
                Label("Arraste para olhar", systemImage: "hand.draw")
                Label("Pinça para zoom", systemImage: "plus.magnifyingglass")
            }
            .font(.App.caption)
            .foregroundColor(.white.opacity(0.6))

            Spacer()
            FOVPill(engine: vm.engine)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .glassPanel(cornerRadius: Theme.R.md)
    }
}

// MARK: - Heading compass

private struct HeadingCompass: View {
    @ObservedObject var engine: ViewerEngine

    var body: some View {
        var d = Double(engine.yaw) * 180 / .pi
        d = d.truncatingRemainder(dividingBy: 360); if d < 0 { d += 360 }

        return ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 58, height: 58)
            Circle()
                .stroke(Theme.cyan.opacity(0.5), lineWidth: 1)
                .frame(width: 58, height: 58)
            Capsule()
                .fill(Theme.cyan)
                .frame(width: 2.5, height: 16)
                .offset(y: -17)
                .rotationEffect(.degrees(-Double(engine.yaw) * 180 / .pi))
            Text("\(Int(d.rounded()))°")
                .font(.App.micro)
                .foregroundColor(.white.opacity(0.85))
                .offset(y: 15)
        }
        .shadow(color: .black.opacity(0.4), radius: 8)
    }
}

// MARK: - FOV pill

private struct FOVPill: View {
    @ObservedObject var engine: ViewerEngine

    var body: some View {
        let zoom = 1.2 / Double(engine.fov)
        return Label(String(format: "%.1fx", zoom), systemImage: "plus.magnifyingglass")
            .font(.App.hud)
            .foregroundColor(.white.opacity(0.85))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .glassPanel(cornerRadius: Theme.R.pill, tint: Theme.violet)
    }
}

// MARK: - Viewport brackets

private struct ViewerBrackets: Shape {
    var inset: CGFloat = 22
    var len: CGFloat = 20
    func path(in r: CGRect) -> Path {
        var p = Path()
        let (x0, y0, x1, y1) = (r.minX, r.minY, r.maxX, r.maxY)
        p.addLines([CGPoint(x: x0 + inset, y: y0 + inset + len), CGPoint(x: x0 + inset, y: y0 + inset), CGPoint(x: x0 + inset + len, y: y0 + inset)])
        p.addLines([CGPoint(x: x1 - inset - len, y: y0 + inset), CGPoint(x: x1 - inset, y: y0 + inset), CGPoint(x: x1 - inset, y: y0 + inset + len)])
        p.addLines([CGPoint(x: x0 + inset, y: y1 - inset - len), CGPoint(x: x0 + inset, y: y1 - inset), CGPoint(x: x0 + inset + len, y: y1 - inset)])
        p.addLines([CGPoint(x: x1 - inset - len, y: y1 - inset), CGPoint(x: x1 - inset, y: y1 - inset), CGPoint(x: x1 - inset, y: y1 - inset - len)])
        return p
    }
}

// MetalContainer was extracted to UI/Components/MetalContainer.swift so the tour
// viewer can reuse the same Metal sphere host.
