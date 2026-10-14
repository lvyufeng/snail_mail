import SwiftUI

/// Title screen: pick a game mode and launch. Shares the deep-space backdrop
/// and mascot with the gameplay screen so the whole game reads as one piece.
struct MenuView: View {
    @State private var selected: GameMode = .tutorial
    @State private var muted = Sound.shared.muted

    var body: some View {
        ZStack {
            SpaceBackground(showPlanet: true)

            GeometryReader { geo in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        SnailMascot()
                            .frame(width: 170, height: 130)
                            .shadow(color: Palette.magenta.opacity(0.5), radius: 18, y: 6)
                            .padding(.top, 34)

                        VStack(spacing: 2) {
                            Text("SNAIL MAIL")
                                .font(.system(size: 46, weight: .black, design: .rounded))
                                .tracking(1)
                                .foregroundStyle(
                                    LinearGradient(colors: [Palette.gold, Palette.goldDeep],
                                                   startPoint: .top, endPoint: .bottom)
                                )
                                .shadow(color: .black.opacity(0.8), radius: 6, y: 3)
                            Text("蜗牛竞速 · Intergalactic Delivery")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Palette.ink.opacity(0.8))
                        }

                        NeonPanel(border: Palette.magenta) {
                            VStack(spacing: 10) {
                                ForEach(GameMode.allCases) { mode in
                                    ModeRow(mode: mode, isSelected: selected == mode) {
                                        selected = mode
                                        Sound.shared.play(.select)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)

                        // The campaign opens on the galaxy map so the player
                        // picks a star; every other mode starts its own route.
                        if selected == .arcade {
                            NavigationLink {
                                LevelSelectView()
                            } label: {
                                ArcadeLabel(title: "SELECT STAR", tint: Palette.good, icon: "★")
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 60)
                        } else {
                            NavigationLink {
                                GameView(mode: selected)
                            } label: {
                                ArcadeLabel(title: "PLAY", tint: Palette.good, icon: "▶")
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 60)
                        }

                        Text("Drag to steer · hold to fire · dodge salt & meteors")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Palette.ink.opacity(0.72))
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 44)
                    }
                    .frame(maxWidth: 420)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geo.size.height)
                    .padding(.horizontal, 20)
                }
            }

            VStack {
                HStack {
                    Spacer()
                    RoundIconButton(icon: .sound(on: !muted)) {
                        muted.toggle()
                        Sound.shared.setMuted(muted)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
        .onAppear { Sound.shared.start() }
    }
}

private struct ModeRow: View {
    let mode: GameMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle()
                    .stroke(Palette.ink.opacity(0.7), lineWidth: 2)
                    .background(
                        Circle().fill(isSelected ? Palette.cyan : Color.clear)
                            .padding(3)
                    )
                    .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(mode.title)
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        Text(mode.chinese)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Palette.gold)
                    }
                    Text(mode.subtitle)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Palette.ink.opacity(0.6))
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Palette.magenta.opacity(0.28) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Palette.cyan.opacity(0.9) : Palette.ink.opacity(0.15),
                            lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}
