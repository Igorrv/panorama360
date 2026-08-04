import SwiftUI

/// Modal sheet for authoring a tour hotspot link: pick the target scene, an SF
/// Symbol, and an optional label, then commit. Owns its own selection state
/// (seeded from the view-model's draft on appear). Extracted from
/// `TourViewerView` to keep both files under the 300-line cap.
struct TourLinkSheet: View {

    @ObservedObject var vm: TourViewerViewModel

    @State private var target: TourScene?
    @State private var label = ""
    @State private var icon = "arrow.right.circle.fill"
    @State private var info = ""

    private static let icons: [(String, String)] = [
        ("arrow.right.circle.fill", "Passagem"),
        ("door.right.hand.open", "Porta"),
        ("arrow.up.circle.fill", "Subir"),
        ("arrow.down.circle.fill", "Descer"),
        ("info.circle.fill", "Info")
    ]

    var body: some View {
        VStack(spacing: 18) {
            Text("Novo ponto de passagem")
                .font(.App.headline).foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            if vm.otherScenes().isEmpty {
                Label("Adicione outra cena a este projeto antes de criar um link.",
                      systemImage: "info.circle")
                    .font(.App.caption).foregroundColor(.white.opacity(0.7))
            } else {
                targetPicker
                iconRow
                TextField("Rótulo (ex.: Cozinha)", text: $label)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color.white.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: Theme.R.md))
                    .foregroundColor(.white)
                TextField("Informação (opcional, ex.: 12m², reformada)", text: $info)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color.white.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: Theme.R.md))
                    .foregroundColor(.white)
                    .lineLimit(1...3)
            }

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Button("Cancelar", role: .cancel) { vm.cancelHotspot() }
                    .frame(maxWidth: .infinity).padding(.vertical, 4)
                    .glassPanel(cornerRadius: Theme.R.md)
                Button {
                    guard let t = target else { return }
                    vm.commitHotspot(targetSceneID: t.id,
                                     label: label.trimmingCharacters(in: .whitespaces).isEmpty
                                            ? t.title : label,
                                     icon: icon,
                                     info: info)
                } label: {
                    Text("Criar link").frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(HoloButton(gradient: Theme.auroraColors, cornerRadius: Theme.R.md))
                .disabled(target == nil)
            }
        }
        .padding(22)
        .background(Color.black.ignoresSafeArea())
        .onAppear { seed() }
    }

    private var targetPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cena de destino").font(.App.micro).foregroundColor(.white.opacity(0.6))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.otherScenes()) { scene in
                        let sel = target?.id == scene.id
                        Button { target = scene } label: {
                            Text(scene.title).font(.App.caption)
                                .foregroundColor(sel ? .black : .white)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(sel ? AnyShapeStyle(Theme.mint) : AnyShapeStyle(Color.white.opacity(0.1)),
                                            in: Capsule())
                        }
                    }
                }
            }
        }
    }

    private var iconRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Self.icons, id: \.0) { ic, text in
                    let sel = icon == ic
                    Button { icon = ic } label: {
                        VStack(spacing: 4) {
                            Image(systemName: ic).font(.system(size: 20))
                            Text(text).font(.system(size: 9))
                        }
                        .foregroundColor(sel ? .black : .white)
                        .frame(width: 58, height: 50)
                        .background(sel ? AnyShapeStyle(Theme.mint) : AnyShapeStyle(Color.white.opacity(0.08)),
                                    in: RoundedRectangle(cornerRadius: Theme.R.sm))
                    }
                }
            }
        }
    }

    private func seed() {
        if target == nil { target = vm.otherScenes().first }
        label = vm.draftHotspot?.label ?? ""
        info = vm.draftHotspot?.info ?? ""
        if let ic = vm.draftHotspot?.iconName { icon = ic }
    }
}
