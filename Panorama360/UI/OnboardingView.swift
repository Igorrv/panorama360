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
             title: "Capture a 360° space",
             body: "Panorama360 guides you through a ring of glowing dots floating over your camera. Photograph each one and it builds an interactive 360° view of the room.",
             accent: .blue),
        Card(icon: "smartphone",
             title: "Hold the phone upright",
             body: "Stand in the middle of the room. Hold the phone vertically at chest height, roughly at arm's length. You stay in one spot — only the phone rotates.",
             accent: .teal),
        Card(icon: "arrow.triangle.2.circlepath.camera",
             title: "Aim, then hold still",
             body: "Slowly turn to bring a dot to the centre. When it turns blue, STOP and hold steady. The photo fires by itself when you're still and in focus — there is no shutter button.",
             accent: .yellow),
        Card(icon: "checkmark.seal.fill",
             title: "One room to start",
             body: "For your first room you'll capture a short ring of 8 dots. Finish them all (or tap Finish) and the app stitches your 360° panorama. Then the full app unlocks.",
             accent: .green)
    ]

    var body: some View {
        ZStack {
            backgroundGradient
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(0..<cards.count, id: \.self) { i in
                        cardView(cards[i]).tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                actionArea
                    .padding(.horizontal, 24)
                    .padding(.bottom, 34)
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - Card

    private func cardView(_ card: Card) -> some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle()
                    .fill(card.accent.opacity(0.16))
                    .frame(width: 150, height: 150)
                Image(systemName: card.icon)
                    .font(.system(size: 60, weight: .regular))
                    .foregroundStyle(card.accent.gradient)
                    .shadow(color: card.accent.opacity(0.6), radius: 18)
            }
            Text(card.title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(card.body)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 30)
            Spacer()
            Spacer()
        }
    }

    // MARK: - Actions

    private var actionArea: some View {
        VStack(spacing: 12) {
            if page == cards.count - 1 {
                Button {
                    router.startTutorial()
                } label: {
                    Label("Start my first room", systemImage: "play.fill")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.blue.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                Button {
                    router.skipOnboarding()
                } label: {
                    Text("Skip — use full capture")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.vertical, 6)
                }
            } else {
                Button {
                    withAnimation { page = min(page + 1, cards.count - 1) }
                } label: {
                    Text("Next")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(.white.opacity(0.18), lineWidth: 1))
                }
                Button {
                    router.skipOnboarding()
                } label: {
                    Text("Skip")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.vertical, 6)
                }
            }
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color(red: 0.05, green: 0.07, blue: 0.14),
                     Color.black],
            startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}
