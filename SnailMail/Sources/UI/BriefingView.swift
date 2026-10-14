import SwiftUI

/// The page the original prints before a route begins: the level's own
/// `GalaxyText:` blurb, Turbo's log entry or an IPS (Intergalactic Postal
/// Service) warning, with a tap to head out on the delivery.
struct BriefingView: View {
    let mode: GameMode
    let level: Int

    @EnvironmentObject private var router: AppRouter

    private var text: String { LevelCatalog.briefing(mode: mode, level: level) ?? "" }

    private var levelName: String {
        switch mode {
        case .arcade:
            let star = LevelCatalog.arcade[max(0, min(level, LevelCatalog.arcade.count - 1))]
            return star.name
        default:
            return mode.title
        }
    }

    private var galaxyName: String? {
        guard mode == .arcade,
              let star = LevelCatalog.arcade.first(where: { $0.id == level }),
              star.galaxy < LevelCatalog.galaxies.count
        else { return nil }
        return "GALAXY \(star.galaxy + 1) · \(LevelCatalog.galaxies[star.galaxy])"
    }

    var body: some View {
        ZStack {
            SpaceBackground(showPlanet: true)

            GeometryReader { geo in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        VStack(spacing: 4) {
                            StatLabel(text: "Postal Briefing", color: Palette.cyan)
                            Text(levelName)
                                .font(.system(size: 30, weight: .black, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(colors: [Palette.gold, Palette.goldDeep],
                                                   startPoint: .top, endPoint: .bottom)
                                )
                                .multilineTextAlignment(.center)
                                .shadow(color: .black.opacity(0.8), radius: 6, y: 3)
                            if let galaxyName {
                                Text(galaxyName)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Palette.ink.opacity(0.7))
                            }
                        }

                        NeonPanel(border: Palette.magenta) {
                            HStack(alignment: .top, spacing: 14) {
                                SnailMascot()
                                    .frame(width: 96, height: 74)
                                Text(text)
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Palette.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 4)
                        }
                        .padding(.horizontal, 20)

                        ArcadeButton(title: "CLICK TO CONTINUE", tint: Palette.good, icon: "▶") {
                            Sound.shared.play(.select)
                            router.push(.game(mode: mode, level: level))
                        }
                        .padding(.horizontal, 40)
                        .padding(.bottom, 40)
                    }
                    .frame(maxWidth: 460)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geo.size.height)
                    .padding(.horizontal, 20)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .statusBarHidden()
        .onAppear { Sound.shared.start() }
    }
}
