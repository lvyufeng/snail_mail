import SwiftUI

/// The original's galaxy map: ten galaxies of five stars, drawn from the names
/// and per-level tuning recovered from the game's data file. Picking a star
/// launches that exact level, so the `level` parameter finally means something.
struct LevelSelectView: View {
    @State private var selectedGalaxy = 0

    var body: some View {
        // The scroll view hands its content an unspecified width, so the
        // column has to be told how wide the screen actually is — otherwise it
        // takes its `maxWidth` cap and the map hangs off both edges.
        ZStack {
            RetailBackdrop(stem: "starmapbg")

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    header
                    StarMapCanvas(selected: $selectedGalaxy)
                        .aspectRatio(GalaxyMapLayout.design.width / GalaxyMapLayout.design.height,
                                     contentMode: .fit)
                        .frame(maxWidth: mapColumn)

                    ForEach(0..<LevelCatalog.galaxies.count, id: \.self) { galaxy in
                        GalaxyPanel(galaxy: galaxy, expanded: galaxy == selectedGalaxy)
                    }
                }
                .frame(width: mapColumn)
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

    /// The scroll view proposes no width to its content, so the column has to
    /// be capped by hand; otherwise the map takes its full `maxWidth` and hangs
    /// off both edges of the phone.
    private var mapColumn: CGFloat {
        min(460, max(280, UIScreen.main.bounds.width - 36))
    }

    private var header: some View {
        VStack(spacing: 4) {
            if let logo = RetailAssets.image("Art/Galaxy/spacemaplogo.png") {
                Image(uiImage: logo)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 46)
            } else {
                // The screen's own title in the retail build (`0x408e31`,
                // 0x4a20fc), drawn where the map's logo art would sit.
                Text("Intergalactic Delivery Route")
                    .font(.retail(34, weight: .black))
                    .tracking(0.5)
                    .foregroundStyle(
                        LinearGradient(colors: [Palette.gold, Palette.goldDeep],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.8), radius: 6, y: 3)
            }
            Text("战役 · \(LevelCatalog.reachableStars) stars across \(LevelCatalog.galaxies.count) galaxies")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.ink.opacity(0.8))
        }
        .padding(.top, 12)
    }
}

/// The galaxy map itself, laid out from the coordinates the retail executable
/// ships (`GalaxyMapLayout`). The build draws the ten portraits at their native
/// 256x256 over a starmap band, threads one continuous line through all fifty
/// stars and marks each level star on top; tapping a star plays it.
private struct StarMapCanvas: View {
    @Binding var selected: Int
    @EnvironmentObject private var router: AppRouter

    /// Levels the player has already posted a score for, so the map can flag
    /// them the way the retail build does.
    private var cleared: Set<Int> {
        let names = Set(HighScores.shared.postal.map(\.level))
        return Set(LevelCatalog.arcade.filter { names.contains($0.name) }.map(\.id))
    }

    /// The star the cursor sits on: the first one the player has not posted a
    /// score for. The build keeps a single `LevelSelect` ring for exactly one
    /// level at a time — the one the arrows point at — and parks it here when
    /// the map opens, so this also reads as "how far you have got".
    private var frontier: Int {
        (0..<LevelCatalog.arcade.count).first { !cleared.contains($0) }
            ?? LevelCatalog.arcade.count - 1
    }

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / GalaxyMapLayout.design.width,
                            geo.size.height / GalaxyMapLayout.design.height)
            let size = CGSize(width: GalaxyMapLayout.design.width * scale,
                              height: GalaxyMapLayout.design.height * scale)
            let x0 = (geo.size.width - size.width) / 2
            let y0 = (geo.size.height - size.height) / 2

            ZStack(alignment: .topLeading) {
                mapBorder
                    .frame(width: size.width, height: size.height)
                    .position(x: x0 + size.width / 2, y: y0 + size.height / 2)

                routeLine(scale: scale, x0: x0, y0: y0)

                ForEach(0..<GalaxyMapLayout.galaxyCentres.count, id: \.self) { g in
                    galaxyNode(g, scale: scale)
                        .position(at(GalaxyMapLayout.point(galaxy: g), scale, x0, y0))
                }

                ForEach(0..<LevelCatalog.arcade.count, id: \.self) { i in
                    starNode(i, scale: scale)
                        .position(at(starPoint(i), scale, x0, y0))
                }
            }
            .frame(width: size.width, height: size.height)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }

    /// The map's star `i` in level order, galaxy-major: `route[g * 5 + s]`.
    private func starPoint(_ i: Int) -> CGPoint {
        let level = LevelCatalog.star(i)
        return GalaxyMapLayout.point(galaxy: level.galaxy, star: level.star)
    }

    private func at(_ p: CGPoint, _ scale: CGFloat, _ x0: CGFloat, _ y0: CGFloat) -> CGPoint {
        CGPoint(x: x0 + p.x * scale, y: y0 + p.y * scale)
    }

    /// The single line the map threads through every star, in level order. The
    /// build stretches one four-unit `LineStar` sprite between each pair of
    /// neighbouring stars, at alpha 0.8 for the legs up to the cursor and 0.2
    /// for the rest, so the map reads as a bright trail with a faint tail.
    @ViewBuilder
    private func routeLine(scale: CGFloat, x0: CGFloat, y0: CGFloat) -> some View {
        let pts = (0..<LevelCatalog.arcade.count).map { starPoint($0) }
        let line = Color(red: 239 / 255, green: 239 / 255, blue: 239 / 255)

        Path { path in
            guard let first = pts.first else { return }
            path.move(to: at(first, scale, x0, y0))
            for p in pts.dropFirst() { path.addLine(to: at(p, scale, x0, y0)) }
        }
        .stroke(line.opacity(0.2),
                style: StrokeStyle(lineWidth: 4 * scale, lineCap: .round, lineJoin: .round))

        Path { path in
            guard pts.count > 1 else { return }
            path.move(to: at(pts[0], scale, x0, y0))
            for i in 1...max(min(frontier, pts.count - 1), 1) {
                path.addLine(to: at(pts[i], scale, x0, y0))
            }
        }
        .stroke(line.opacity(0.8),
                style: StrokeStyle(lineWidth: 4 * scale, lineCap: .round, lineJoin: .round))
    }

    @ViewBuilder
    private var mapBorder: some View {
        if let img = RetailAssets.image("Art/Galaxy/borderspacemap.png") {
            Image(uiImage: img).resizable()
        } else {
            RoundedRectangle(cornerRadius: 2)
                .stroke(Palette.cyan.opacity(0.4), lineWidth: 2)
        }
    }

    /// The build marks every level on the map with the same white `LevelStar`
    /// sprite at its native 32 units, and parks the 64-unit `LevelSelect` ring
    /// on the single level the cursor points at.
    @ViewBuilder
    private func starNode(_ i: Int, scale: CGFloat) -> some View {
        let level = LevelCatalog.star(i)
        ZStack {
            if let star = RetailAssets.image("Art/Galaxy/levelstar.png") {
                Image(uiImage: star).resizable().scaledToFit().frame(width: 32 * scale)
            } else {
                StarBadge(color: .white).frame(width: 20 * scale)
            }
            if i == frontier, let ring = RetailAssets.image("Art/Galaxy/levelselect.png") {
                Image(uiImage: ring).resizable().scaledToFit().frame(width: 64 * scale)
            }
        }
        .frame(width: 64 * scale, height: 64 * scale)
        .contentShape(Rectangle())
        .onTapGesture { open(level) }
        // The star is a bare `ZStack` over a `Canvas`, so without these
        // VoiceOver sees the whole map as one unlabelled element and no level
        // can be chosen at all. The label says what the drawing says: which
        // star, its name, and whether it has been posted.
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Star \(level.star + 1), \(level.name)\(cleared.contains(i) ? ", cleared" : "")")
        .accessibilityHint(i == frontier ? "Your next route" : "Play this route")
        .accessibilitySortPriority(Double(50 - i))
    }

    @ViewBuilder
    private func galaxyNode(_ g: Int, scale: CGFloat) -> some View {
        let isSelected = g == selected
        ZStack {
            if let img = RetailAssets.image(String(format: "Art/Galaxy/galaxy%03d.png", g)) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 256 * scale)
            } else {
                StarBadge(color: isSelected ? Palette.gold : Palette.ink.opacity(0.75))
                    .frame(width: 40 * scale)
            }
            if isSelected, let ring = RetailAssets.image("Art/Galaxy/galaxyselect.png") {
                Image(uiImage: ring).resizable().scaledToFit().frame(width: 128 * scale)
            }
        }
        .frame(width: 256 * scale, height: 256 * scale)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) { selected = g }
            // Moving the star-map cursor: the retail build keeps a pair of
            // servo samples for exactly this.
            Sound.shared.play(.servo)
        }
        // Portraits are also bare artwork; VoiceOver needs to know this moves
        // the cursor rather than starting anything.
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("Galaxy \(g + 1), \(LevelCatalog.galaxies[g])")
        .accessibilityHint("Show this galaxy's stars")
    }

    private func open(_ level: ArcadeLevel) {
        withAnimation(.easeInOut(duration: 0.2)) { selected = level.galaxy }
        Sound.shared.play(.select)
        if LevelCatalog.briefing(mode: .arcade, level: level.id) != nil {
            router.push(.briefing(mode: .arcade, level: level.id))
        } else {
            router.push(.game(mode: .arcade, level: level.id))
        }
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
                        .font(.retail(12, weight: .heavy))
                        .foregroundStyle(Palette.gold)
                    Spacer(minLength: 4)
                    Text(LevelCatalog.galaxies[galaxy])
                        .font(.retail(11, weight: .medium))
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
                    .font(.retail(15, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("Star \(level.star + 1) * \(level.speed) Gph * \(level.parcels) parcels")
                    .font(.retail(10, weight: .medium))
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
