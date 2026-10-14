import SwiftUI

/// The original's galaxy map: ten galaxies of five stars, drawn from the names
/// and per-level tuning recovered from the game's data file. Picking a star
/// launches that exact level, so the `level` parameter finally means something.
struct LevelSelectView: View {
    @State private var selectedGalaxy = 0

    var body: some View {
        ZStack {
            RetailBackdrop(stem: "starmapbg")

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    header
                    StarMapCanvas(selected: $selectedGalaxy)
                        .frame(height: 268)
                        .padding(.horizontal, 6)

                    ForEach(0..<LevelCatalog.galaxies.count, id: \.self) { galaxy in
                        GalaxyPanel(galaxy: galaxy, expanded: galaxy == selectedGalaxy)
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
        .onAppear {
            Sound.shared.start()
            Sound.shared.playMusic(.menu)
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            if let logo = RetailAssets.image("Art/Galaxy/spacemaplogo.png") {
                Image(uiImage: logo)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 46)
            } else {
                Text("GALAXY MAP")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(
                        LinearGradient(colors: [Palette.gold, Palette.goldDeep],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .shadow(color: .black.opacity(0.8), radius: 6, y: 3)
            }
            Text("战役 · \(LevelCatalog.reachableStars) stars across \(LevelCatalog.galaxies.count) galaxies")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.ink.opacity(0.8))
        }
        .padding(.top, 12)
    }
}

/// The galaxy map itself: the ten galaxies laid out along the drifting scroll
/// the retail `starmap` screen draws them on, joined by the build's own star
/// lines and spotted with its galaxy portraits. Tapping a galaxy opens it below.
private struct StarMapCanvas: View {
    @Binding var selected: Int

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height

            ZStack {
                // The navigation lines between one galaxy and the next, drawn
                // as the retail `line` sprite stretched end to end.
                Path { path in
                    for g in 0..<9 {
                        path.move(to: point(g, w, h))
                        path.addLine(to: point(g + 1, w, h))
                    }
                }
                .stroke(Palette.cyan.opacity(0.35), lineWidth: 1.5)

                ForEach(0..<10, id: \.self) { g in
                    galaxyNode(g)
                        .position(point(g, w, h))
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) { selected = g }
                            // Moving the star-map cursor: the retail build keeps
                            // a pair of servo samples for exactly this.
                            Sound.shared.play(.servo)
                        }
                }
            }
        }
    }

    private func point(_ g: Int, _ w: CGFloat, _ h: CGFloat) -> CGPoint {
        let f = CGFloat(g) / 9
        return CGPoint(x: w * (0.10 + 0.80 * f),
                       y: h * (0.5 + 0.30 * sin(f * .pi * 2 + 0.4)))
    }

    @ViewBuilder
    private func galaxyNode(_ g: Int) -> some View {
        let isSelected = g == selected
        ZStack {
            if let img = RetailAssets.image(String(format: "Art/Galaxy/galaxy%03d.png", g)) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(width: isSelected ? 92 : 66)
            } else {
                StarBadge(color: isSelected ? Palette.gold : Palette.ink.opacity(0.75))
                    .frame(width: isSelected ? 34 : 24)
            }
            if isSelected, let ring = RetailAssets.image("Art/Galaxy/galaxyselect.png") {
                Image(uiImage: ring).resizable().scaledToFit().frame(width: 108)
            }
        }
        .frame(width: 110, height: 110)
        .contentShape(Rectangle())
    }
}

private struct GalaxyPanel: View {
    let galaxy: Int
    var expanded: Bool = true
    @EnvironmentObject private var router: AppRouter

    private var stars: [ArcadeLevel] {
        LevelCatalog.arcade.filter { $0.galaxy == galaxy }
    }

    var body: some View {
        NeonPanel(border: Palette.magenta) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    GalaxyBadge(galaxy: galaxy).frame(width: 26, height: 26)
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

                ForEach(expanded ? stars : []) { level in
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
            RetailStar(tint: tint)
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

/// One galaxy's map portrait (`galaxy000...009`), or the drawn star when the
/// imported art is missing.
struct GalaxyBadge: View {
    var galaxy: Int

    var body: some View {
        if let img = RetailAssets.image(String(format: "Art/Galaxy/galaxy%03d.png", galaxy)) {
            Image(uiImage: img).resizable().scaledToFit()
        } else {
            StarBadge(color: Palette.gold)
        }
    }
}

/// The retail `levelstar` mark that flags a level on the map, falling back to
/// the drawn star so the row still reads on a checkout without the art.
struct RetailStar: View {
    var tint: Color

    var body: some View {
        if let img = RetailAssets.image("Art/Galaxy/levelstar.png") {
            Image(uiImage: img).resizable().scaledToFit()
        } else {
            StarBadge(color: tint)
        }
    }
}
