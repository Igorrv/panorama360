import SwiftUI

/// Lists a project's scenes, lets the user add a new scene (capture → stitch),
/// start the tour, and remove scenes. Reuses the app's dark glass aesthetic.
struct ProjectDetailView: View {

    let projectID: UUID
    @StateObject private var vm: ProjectDetailViewModel
    @EnvironmentObject private var router: AppRouter

    init(projectID: UUID) {
        self.projectID = projectID
        _vm = StateObject(wrappedValue: ProjectDetailViewModel(projectID: projectID))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                if let project = vm.project {
                    if project.scenes.isEmpty {
                        emptyState
                    } else {
                        sceneList(project)
                    }
                }
                Spacer(minLength: 0)
                bottomBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
            }
        }
        .tint(Theme.cyan)
        .onAppear { vm.reload() }
    }

    // MARK: - Header

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { router.goLibrary() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .glassPanel(cornerRadius: 22)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.project?.title ?? "Projeto")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("\(vm.project?.scenes.count ?? 0) cena(s)")
                    .font(.App.micro)
                    .foregroundColor(.white.opacity(0.5))
            }
            Spacer()
            Button {
                router.goTourViewer(projectID)
            } label: {
                Label("Tour", systemImage: "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16).frame(height: 40)
            }
            .buttonStyle(HoloButton(gradient: vm.canStartTour ? Theme.auroraColors : [Color.gray.opacity(0.4), Color.gray.opacity(0.4)],
                                    cornerRadius: Theme.R.md))
            .disabled(!vm.canStartTour)
        }
    }

    // MARK: - Scene list

    private func sceneList(_ project: Project) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(Array(project.scenes.enumerated()), id: \.element.id) { idx, scene in
                    SceneRow(index: idx + 1, scene: scene, ready: vm.equirectReady(scene)) {
                        vm.deleteScene(scene)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44))
                .foregroundColor(Theme.cyan.opacity(0.7))
            Text("Nenhuma cena")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
            Text("Toque em “Adicionar cena” para capturar o primeiro cômodo 360°.")
                .font(.App.caption)
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Spacer()
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        Button { router.beginAddScene(to: projectID) } label: {
            Label("Adicionar cena", systemImage: "plus.viewfinder")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(HoloButton(gradient: Theme.auroraColors, cornerRadius: Theme.R.md))
    }
}

// MARK: - Scene row

private struct SceneRow: View {
    let index: Int
    let scene: TourScene
    let ready: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.auroraGradient.opacity(0.3))
                Text("\(index)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(scene.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                HStack(spacing: 8) {
                    Label("\(scene.hotspots.count)", systemImage: "arrow.triangle.swap")
                    if ready {
                        Label("Pronta", systemImage: "checkmark.circle.fill")
                            .foregroundColor(Theme.mint)
                    } else {
                        Label("Sem panorama", systemImage: "exclamationmark.triangle")
                            .foregroundColor(Theme.amber)
                    }
                }
                .font(.App.micro)
                .foregroundColor(.white.opacity(0.6))
            }
            Spacer()
        }
        .padding(12)
        .glassPanel(cornerRadius: Theme.R.md)
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Excluir cena", systemImage: "trash")
            }
        }
    }
}
