import SwiftUI

/// Home base: a grid of tour `Project`s. Create a project, open it to add
/// scenes, or run a standalone capture (the original flow) via "Captura avulsa".
struct LibraryView: View {

    @StateObject private var vm = LibraryViewModel()
    @EnvironmentObject private var router: AppRouter

    @State private var showCreate = false
    @State private var newProjectName = ""

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                if vm.projects.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
        }
        .tint(Theme.cyan)
        .onAppear { vm.reload() }
        .alert("Novo projeto", isPresented: $showCreate) {
            TextField("Nome do projeto", text: $newProjectName)
            Button("Criar") { createAndOpen() }
            Button("Cancelar", role: .cancel) { newProjectName = "" }
        } message: {
            Text("Dê um nome ao seu tour (ex.: Apartamento, Casa).")
        }
    }

    // MARK: - Header

    private var topBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Projetos")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Tours 360°")
                    .font(.App.caption)
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer()
            Button { showCreate = true } label: {
                Label("Novo", systemImage: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16).frame(height: 40)
            }
            .buttonStyle(HoloButton(gradient: Theme.auroraColors, cornerRadius: Theme.R.md))
        }
    }

    // MARK: - Grid

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(vm.projects) { project in
                    Button { router.goProjectDetail(project.id) } label: {
                        ProjectCard(project: project)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            vm.deleteProject(project)
                        } label: {
                            Label("Excluir", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "pano.fill")
                .font(.system(size: 48))
                .foregroundColor(Theme.cyan.opacity(0.7))
            Text("Nenhum projeto ainda")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
            Text("Toque em “Novo” para criar seu primeiro tour 360°.")
                .font(.App.caption)
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
            Button { router.goCapture() } label: {
                Label("Captura avulsa", systemImage: "camera")
                    .font(.App.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 14).padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .tint(.white.opacity(0.25))
            .padding(.bottom, 28)
        }
    }

    // MARK: - Actions

    private func createAndOpen() {
        let name = newProjectName
        newProjectName = ""
        if let id = vm.createProject(title: name) {
            router.goProjectDetail(id)
        }
    }
}

// MARK: - Card

private struct ProjectCard: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.R.md)
                    .fill(LinearGradient(colors: Theme.auroraColors.map { $0.opacity(0.32) },
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "pano.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white.opacity(0.85))
            }
            .frame(height: 108)

            Text(project.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)

            HStack(spacing: 6) {
                Label("\(project.scenes.count)", systemImage: "photo.on.rectangle")
                Spacer()
                Text(project.updatedAt.formatted(date: .abbreviated, time: .omitted))
            }
            .font(.App.micro)
            .foregroundColor(.white.opacity(0.6))
        }
        .padding(10)
        .glassPanel(cornerRadius: Theme.R.lg)
    }
}
