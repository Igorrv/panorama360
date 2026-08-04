import SwiftUI

/// Modal sheet for per-project branding: a brand accent colour plus an optional
/// broker/agency name and contact (phone/WhatsApp). Realtors see their identity
/// inside the tour. All fields optional ⇒ branding hides until set. Preset
/// swatches keep the picker free of iOS-version risk and on the scanner palette.
struct BrandingSheet: View {

    @ObservedObject var vm: ProjectDetailViewModel
    @Environment(\.dismiss) private var dismiss

    /// "#RRGGBB"; nil ⇒ app cyan (the "Padrão" swatch).
    @State private var accent: String? = nil
    @State private var brokerName: String = ""
    @State private var brokerContact: String = ""

    private let swatches: [(hex: String, label: String)] = [
        ("#33D9FF", "Ciano"),   ("#8C73FF", "Violeta"), ("#33F273", "Verde"),
        ("#FFCC33", "Âmbar"),   ("#2D7FF9", "Azul"),    ("#B14BFF", "Roxo"),
        ("#FF5C8A", "Rosa"),    ("#FF5252", "Vermelho")
    ]

    var body: some View {
        VStack(spacing: 20) {
            Text("Identidade do tour")
                .font(.App.headline).foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            swatchRow
            fields
            Spacer(minLength: 0)
            saveRow
        }
        .padding(22)
        .background(Color.black.ignoresSafeArea())
        .onAppear { seed() }
    }

    private var swatchRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cor de destaque").font(.App.micro).foregroundColor(.white.opacity(0.6))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 14) {
                defaultSwatch
                ForEach(swatches, id: \.hex) { sw in swatchButton(sw) }
            }
        }
    }

    private var defaultSwatch: some View {
        let sel = accent == nil
        return Button { accent = nil } label: {
            swatchLabel(color: Theme.cyan, glyph: "sparkles", text: "Padrão", selected: sel)
        }
    }

    private func swatchButton(_ sw: (hex: String, label: String)) -> some View {
        let sel = accent == sw.hex
        return Button { accent = sw.hex } label: {
            swatchLabel(color: Theme.color(fromHex: sw.hex), glyph: nil,
                        text: sw.label, selected: sel)
        }
    }

    private func swatchLabel(color: Color, glyph: String?, text: String, selected: Bool) -> some View {
        VStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 38, height: 38)
                .overlay {
                    if let glyph { Image(systemName: glyph).font(.system(size: 14)).foregroundColor(.black) }
                    if selected { Circle().stroke(.white, lineWidth: 3).padding(-4) }
                }
            Text(text).font(.system(size: 10)).foregroundColor(.white.opacity(0.82))
        }
    }

    private var fields: some View {
        VStack(spacing: 12) {
            TextField("Corretor / imobiliária (ex.: Ana Souza — CRECI 12345)", text: $brokerName)
                .brandingField()
            TextField("Contato (telefone / WhatsApp)", text: $brokerContact)
                .brandingField()
                .keyboardType(.phonePad)
        }
    }

    private var saveRow: some View {
        HStack(spacing: 12) {
            Button("Cancelar", role: .cancel) { dismiss() }
                .frame(maxWidth: .infinity).padding(.vertical, 4)
                .glassPanel(cornerRadius: Theme.R.md)
            Button {
                vm.updateBranding(accentHex: accent,
                                  brokerName: brokerName,
                                  brokerContact: brokerContact)
                dismiss()
            } label: {
                Text("Salvar").frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(HoloButton(gradient: Theme.auroraColors, cornerRadius: Theme.R.md))
        }
    }

    private func seed() {
        accent = vm.project?.accentHex
        brokerName = vm.project?.brokerName ?? ""
        brokerContact = vm.project?.brokerContact ?? ""
    }
}

private extension View {
    /// Shared text-field look for the branding form.
    func brandingField() -> some View {
        textFieldStyle(.plain)
            .padding(12)
            .background(Color.white.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: Theme.R.md))
            .foregroundColor(.white)
    }
}
