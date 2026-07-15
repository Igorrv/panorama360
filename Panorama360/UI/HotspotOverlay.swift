import SwiftUI

/// Projects the current scene's hotspots onto the viewport and renders a tappable
/// marker at each live screen position. The container ZStack has **no background**
/// on purpose: transparent areas don't capture touches, so panorama drags fall
/// straight through to the Metal layer beneath — only the marker pills are
/// hit-testable. Positions re-project every frame the engine publishes (drag /
/// gyro / zoom), so markers track the view like the capture guide do.
struct HotspotOverlay: View {

    @ObservedObject var engine: ViewerEngine
    @ObservedObject var vm: TourViewerViewModel
    let editMode: Bool
    let onTap: (Hotspot) -> Void
    let onDelete: (UUID) -> Void

    var body: some View {
        let projected = vm.projectedHotspots()
        ZStack {
            ForEach(projected) { p in
                if let pos = p.position {
                    marker(for: p)
                        .position(pos)
                        .scaleEffect(p.scale)
                        .opacity(targetAlive(p.hotspot) ? 1 : 0.3)
                }
            }
        }
        .frame(width: vm.viewportSize.width, height: vm.viewportSize.height)
        // Children (buttons) capture taps; empty space passes drags through.
        .animation(.easeInOut(duration: 0.2), value: editMode)
    }

    @ViewBuilder
    private func marker(for p: TourViewerViewModel.ProjectedHotspot) -> some View {
        let h = p.hotspot
        ZStack(alignment: .topTrailing) {
            Button { onTap(h) } label: {
                HStack(spacing: 7) {
                    Image(systemName: h.iconName)
                        .font(.system(size: 14, weight: .bold))
                    Text(vm.targetTitle(for: h))
                        .font(.App.caption)
                        .lineLimit(1)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Theme.cyan.opacity(0.6), lineWidth: 1))
                .shadow(color: Theme.cyan.opacity(0.4), radius: 8)
                .contentShape(Capsule())
            }
            .disabled(editMode)

            if editMode {
                Button { onDelete(h.id) } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 19))
                        .foregroundColor(Theme.amber)
                        .background(Circle().fill(.black.opacity(0.55)))
                }
                .offset(x: 6, y: -6)
            }
        }
    }

    /// A hotspot pointing at a deleted scene shows but is dimmed + untappable.
    private func targetAlive(_ h: Hotspot) -> Bool {
        vm.targetTitle(for: h) != "Cena removida"
    }
}
