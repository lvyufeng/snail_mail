import SwiftUI

/// The original's galaxy map: ten galaxies of five stars, drawn from the names
/// and per-level tuning recovered from the game's data file. Picking a star
/// launches that exact level, so the `level` parameter finally means something.
struct LevelSelectView: View {
    var body: some View {
        ZStack {
            SpaceBackground(showPlanet: true)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    VStack(spacing: 2) {
                        Text("GALAXY MAP")
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(
                                LinearGradient(colors: [Palette.gold, Palette.goldDeep],
                                               startPoint: .top, endPoint: .bottom)
                            )
                            .shadow(color: .black.opacity(0.8), radius: 6, y: 3)
                        Text("战役 · \(LevelCatalog.reachableStars) stars across \(LevelCatalog.galaxies.count) galaxies")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Palette.ink.opacity(0.8))
                    }
                    .padding(.top, 12)

                    ForEach(0..<LevelCatalog.galaxies.count, id: \.self) { galaxy in
                        GalaxyPanel(galaxy: galaxy)
                    }
                }
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .statusBarHidden()
    }
}

private struct GalaxyPanel: View {
    let galaxy: Int
    @EnvironmentObject private var router: AppRouter

    private var stars: [ArcadeLevel] {
        LevelCatalog.arcade.filter { $0.galaxy == galaxy }
    }

    var body: some View {
        NeonPanel(border: Palette.magenta) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    StarBadge(color: Palette.gold).frame(width: 20, height: 20)
                    Text("GALAXY \(galaxy + 1)")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(Palette.gold)
                    Spacer(minLength: 4)
                    Text(LevelCatalog.galaxies[galaxy])
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Palette.ink.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                ForEach(stars) { level in
                    Button {
                        Sound.shared.play(.select)
                        // The original prints the level's GalaxyText briefing
                        // before the route starts; skip straight in where a
                        // level carries none.
                        if LevelCatalog.briefing(mode: .arcade, level: level.id) != nil {
                            router.push(.briefing(mode: .arcade, level: level.id))
                        } else {
                            router.push(.game(mode: .arcade, level: level.id))
                        }
                    } label: {
                        StarRow(level: level)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct StarRow: View {
    let level: ArcadeLevel

    private var tint: Color {
        switch level.fringe.y {
        case ..<120: Palette.magenta
        case ..<210: Palette.gold
        default: Palette.cyan
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            StarBadge(color: tint)
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(level.name)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("Star \(level.star + 1) · \(level.speed) Gph · \(level.parcels) parcels")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.ink.opacity(0.6))
            }

            Spacer(minLength: 6)

            // The level's own fringe colour, straight from the data file.
            Circle()
                .fill(Color(red: level.fringe.x / 255,
                            green: level.fringe.y / 255,
                            blue: level.fringe.z / 255))
                .frame(width: 18, height: 18)
                .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.45), lineWidth: 1)
        )
    }
}

/// Five-point star drawn from primitives so it matches the rest of the kit.
struct StarBadge: View {
    var color: Color = .white

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let cx = w / 2, cy = h / 2
            let outer = min(w, h) / 2
            let inner = outer * 0.44
            var path = Path()
            for i in 0..<10 {
                let radius = i.isMultiple(of: 2) ? outer : inner
                let angle = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5
                let point = CGPoint(x: cx + cos(angle) * radius, y: cy + sin(angle) * radius)
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
            ctx.fill(path, with: .color(color))
        }
    }
}
