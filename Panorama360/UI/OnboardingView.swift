import SwiftUI

/// First-launch tutorial. A few swipeable cards teach the user how to capture a
/// room; the final card starts a guided **first room** using a small (8-point)
/// sphere so the whole capture → stitch → viewer loop succeeds quickly. After
/// that room is viewed, onboarding is marked complete and the full app unlocks.
struct OnboardingView: View {

    @EnvironmentObject private var router: AppRouter
    @State private var page = 0

    private struct Card {
        let icon: String
        let title: String
        let body: String
        let accent: Color
    }

    private let cards: [Card] = [
        Card(icon: "pano.fill",
             title: "Escaneie um ambiente 360°",
             body: "O Panorama360 te guia por pontos brilhantes sobre a câmera. Conforme você fotografa cada um, o ambiente vai se montando aos poucos em um globo 360° — uma vaga após a outra, como um quebra-cabeça.",
             accent: Theme.cyan),
        Card(icon: "smartphone",
             title: "Segure o celular na vertical",
             body: "Fique no centro do cômodo. Segure o celular na vertical, na altura do peito, a um braço de distância. Você fica parado no mesmo lugar — só o celular gira.",
             accent: Theme.violet),
        Card(icon: "arrow.triangle.2.circlepath.camera",
             title: "Mire e fique parado",
             body: "Vire devagar para trazer um ponto ao centro. Quando ele ficar verde e o anel de mira se completar, PARE e segure firme. A foto sai sozinha quando você está parado e focado — não há botão de disparo.",
             accent: Theme.amber),
        Card(icon: "checkmark.seal.fill",
             title: "Comece com um cômodo",
             body: "No primeiro cômodo você captura um anel curto de 8 pontos. A cada foto o globo se preenche; ao final (ou tocando em Finalizar) o panorama 360° fica pronto e o app completo desbloqueia.",
             accent: Theme.mint)
    ]

    var body: some View {
        ZStack {
            HoloBackground()
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(0..<cards.count, id: \.self) { i in
                        cardView(cards[i]).tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                pageIndicator
                    .padding(.bottom, 18)

                actionArea
                    .padding(.horizontal, 24)
                    .padding(.bottom, 34)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Card

    private func cardView(_ card: Card) -> some View {
        VStack(spacing: 22) {
            Spacer()
            hero(card)
            Spacer()
            VStack(spacing: 14) {
                Text(card.title)
                    .font(.App.title)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text(card.body)
                    .font(.App.body)
                    .foregroundColor(.white.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(24)
            .frame(maxWidth: 360)
            .glassPanel(cornerRadius: Theme.R.lg, tint: card.accent)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    /// Hero icon inside a rotating tick ring with a soft glow.
    private func hero(_ card: Card) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [card.accent.opacity(0.45), .clear],
                                     center: .center, startRadius: 0, endRadius: 95))
                .frame(width: 190, height: 190)
            HUDRing(tickCount: 36, rotationSeconds: 18, color: card.accent)
                .frame(width: 152, height: 152)
            Image(systemName: card.icon)
                .font(.system(size: 58, weight: .regular))
                .foregroundColor(card.accent)
                .shadow(color: card.accent.opacity(0.6), radius: 18)
        }
    }

    // MARK: - Page indicator

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<cards.count, id: \.self) { i in
                Capsule()
                    .fill(i == page
                          ? AnyShapeStyle(Theme.aurora)
                          : AnyShapeStyle(Color.white.opacity(0.25)))
                    .frame(width: i == page ? 28 : 8, height: 8)
                    .animation(Theme.spring, value: page)
            }
        }
    }

    // MARK: - Actions

    private var actionArea: some View {
        VStack(spacing: 12) {
            if page == cards.count - 1 {
                Button {
                    router.startTutorial()
                } label: {
                    Label("Começar meu primeiro cômodo", systemImage: "play.fill")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                }
                .buttonStyle(HoloButton(gradient: Theme.auroraColors, cornerRadius: Theme.R.md))

                Button {
                    router.skipOnboarding()
                } label: {
                    Text("Pular — usar captura completa")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.vertical, 6)
                }
            } else {
                Button {
                    withAnimation(Theme.spring) { page = min(page + 1, cards.count - 1) }
                } label: {
                    Text("Avançar")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                }
                .buttonStyle(HoloButton(gradient: nil, cornerRadius: Theme.R.md))

                Button {
                    router.skipOnboarding()
                } label: {
                    Text("Pular")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.vertical, 6)
                }
            }
        }
    }
}
