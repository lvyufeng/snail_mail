import SwiftUI

/// The in-race HUD, drawn from the retail build's own artwork.
///
/// Every element keeps the place and the size the 2005 HUD gave it. The retail
/// build laid its chrome out on a 640x480 frame, so this view hands out one
/// factor for widths — `s`, the screen's width over 640 — so every sprite is
/// drawn at its own pixel size times `s` and never stretched sideways, and a
/// second one for heights — `sy`, the screen's height over 480 — so an element
/// sits at the same fraction of the frame the original put it at. A portrait
/// screen is a taller 640x480 frame: the HUD's top row keeps to the top, its
/// bottom row keeps to the bottom, and the two rails down the sides grow to
/// bridge them, the way the original's postal meter runs from y=70 all the way
/// to the bottom edge of the frame.
///
/// When `tools/import_art.py` has not put the art in the bundle the elements
/// fall back to plain shapes, so the HUD is always readable.
struct HUDView: View {
    let state: RaceState
    let mode: GameMode
    let onPrimary: () -> Void
    let onPause: () -> Void
    @State private var muted = Sound.shared.muted

    var body: some View {
        GeometryReader { geo in
            // The retail frame is 640 pixels wide; `s` turns its pixels into
            // this screen's points. `sy` does the same for the frame's height,
            // so the rails stretch down the screen instead of keeping their
            // 480-tall proportion.
            let s = geo.size.width / 640
            let sy = geo.size.height / 480

            ZStack {
                routeSpine(scale: s, vScale: sy)

                topRow(scale: s, vScale: sy, height: geo.size.height)

                if mode == .tutorial, state.phase == .running,
                   !state.tutorialMessage.isEmpty {
                    VStack {
                        TutorialBanner(text: state.tutorialMessage, scale: s)
                            .padding(.horizontal, 22 * s)
                            .padding(.top, 118 * sy)
                        Spacer(minLength: 0)
                    }
                    .transition(.opacity)
                }

                bottomStack(scale: s, vScale: sy)

                if state.phase == .ready {
                    VStack(spacing: 12) {
                        Text("DRAG to steer · HOLD to fire")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Palette.ink.opacity(0.85))
                        Button(action: onPrimary) {
                            ArcadeLabel(title: "TAP TO START", tint: Palette.cyan)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: 260)
                    }
                    .padding(.bottom, 60)
                }

                if state.phase == .paused {
                    Text("PAUSED")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .tracking(6)
                        .foregroundStyle(Palette.ink)
                        .shadow(color: Palette.cyan.opacity(0.7), radius: 12)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: state.phase)
        }
    }

    // MARK: - Corners

    /// The parcel counter on the left and the postal meter on the right. The
    /// original pinned the counter's icon at (15, 58) and the meter at
    /// (560, 70) in its 640x480 frame and let the meter run from there to the
    /// bottom edge of the frame; those are the offsets here.
    private func topRow(scale s: CGFloat, vScale sy: CGFloat,
                        height: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                ParcelCounter(state: state, mode: mode, scale: s)
                    .padding(.leading, 15 * s)
                    .padding(.top, 58 * sy)

                Spacer(minLength: 0)

                PostalMeter(fraction: state.meterFraction,
                            invincible: state.invincible,
                            scale: s)
                    .frame(width: 64 * s, height: max(1, height - 70 * sy))
                    .padding(.trailing, 16 * s)
                    .padding(.top, 70 * sy)
            }

            Spacer(minLength: 0)
        }
    }

    /// The route spine: the vertical bar the original ran down the left edge.
    /// Its cursor travelled between y=98 and y=450 of the 640x480 frame, which
    /// is the band this reproduces.
    private func routeSpine(scale s: CGFloat, vScale sy: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0).frame(height: 98 * sy)
            HStack(spacing: 0) {
                RouteSpine(progress: state.progress, scale: s)
                    .frame(width: 64 * s, height: 352 * sy)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
    }

    /// Bottom of the screen: the two "Parcel Collect"/"Parcel Deliver" gauges
    /// at the size the retail file draws them, the lives the snail has left and
    /// the touch controls the PC build did not need. The original's lowest row —
    /// the life icon at y=430 of 480 — is what the padding here keeps clear of
    /// the bottom edge.
    private func bottomStack(scale s: CGFloat, vScale sy: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            HStack(spacing: 0) {
                ParcelGauges(collect: state.collectFraction,
                             deliver: state.deliverFraction,
                             scale: s)
                Spacer(minLength: 0)
            }
            .padding(.leading, 15 * s)

            HStack(spacing: 0) {
                LifeCounter(state: state, scale: s)
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    RoundIconButton(icon: .sound(on: !muted)) {
                        muted.toggle()
                        Sound.shared.setMuted(muted)
                    }
                    RoundIconButton(icon: state.phase == .paused ? .play : .pause,
                                    action: onPause)
                }
            }
            .padding(.horizontal, 15 * s)
            .padding(.top, 10)
            .padding(.bottom, 18 * sy)
        }
    }
}

// MARK: - Postal meter

/// The health gauge: the retail tube down the right edge, filled from the
/// bottom with the artwork the original swapped in for that state — the violet
/// `damageguage` while the snail is holding on, the hot pink `damageguagefull`
/// at a full meter and the bright wash of `damageguagebright` while a pickup
/// has it invincible.
private struct PostalMeter: View {
    let fraction: Double
    let invincible: Bool
    let scale: CGFloat

    private var clamped: Double { min(1, max(0, fraction)) }

    /// Which of the three retail gauges the run is showing.
    private var sprite: String {
        if invincible { return "damageguagebright" }
        if clamped >= 0.995 { return "damageguagefull" }
        return "damageguage"
    }

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            ZStack(alignment: .bottom) {
                // The empty tube behind the fill: the same artwork, spent.
                if RetailAssets.installed {
                    GaugeTube(sprite: "damageguage", scale: scale, height: h)
                        .opacity(0.32)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.45))
                        .frame(width: 64 * scale, height: h)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Palette.ink.opacity(0.55), lineWidth: 1.5)
                        )
                }

                GaugeTube(sprite: sprite, scale: scale, height: h)
                    .frame(height: h * clamped, alignment: .bottom)
                    .frame(height: h, alignment: .bottom)
                    .clipped()
                    .animation(.easeOut(duration: 0.2), value: clamped)
            }
        }
    }
}

/// One retail meter sprite, held together at any height: the file carries a
/// fixed fitting in rows 1...33 and another in rows 352...393 with a flat run
/// of tube between them, so a tall screen stretches only the run.
private struct GaugeTube: View {
    let sprite: String
    let scale: CGFloat
    let height: CGFloat

    var body: some View {
        let path = "Art/Sprites/\(sprite).png"
        let width = 64 * scale
        let capTop = 33 * scale
        let capBottom = 42 * scale
        let run = max(1, height - capTop - capBottom)

        VStack(spacing: 0) {
            piece(path, y: 1, rows: 33, width: width, height: capTop)
            piece(path, y: 34, rows: 318, width: width, height: run)
            piece(path, y: 352, rows: 42, width: width, height: capBottom)
        }
        .frame(width: width, height: height, alignment: .top)
    }

    @ViewBuilder
    private func piece(_ path: String, y: Int, rows: Int,
                       width: CGFloat, height: CGFloat) -> some View {
        if let cut = RetailAssets.band(path, y: y, height: rows) {
            Image(uiImage: cut)
                .resizable()
                .interpolation(.medium)
                .frame(width: width, height: height)
        } else {
            Rectangle()
                .fill(Palette.magenta)
                .frame(width: width, height: height)
        }
    }
}

// MARK: - Route spine

/// The vertical route bar on the left edge and the cursor that slides down it.
/// The retail tube is 13 pixels wide inside its 64-pixel canvas, so the bar is
/// drawn thin the way the original drew it.
private struct RouteSpine: View {
    let progress: Double
    let scale: CGFloat

    private var clamped: Double { min(1, max(0, progress)) }

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let centre = 31 * scale
            let lineWidth = 13 * scale
            let cursorH = 61 * scale
            let cursorTop = (h - cursorH) * clamped

            ZStack(alignment: .top) {
                if let track = RetailAssets.billboardImage("Art/Sprites/progress-bar.png") {
                    Image(uiImage: track)
                        .resizable()
                        .interpolation(.medium)
                        .frame(width: lineWidth, height: h)
                        .position(x: centre, y: h / 2)
                } else {
                    Capsule()
                        .fill(Color.black.opacity(0.4))
                        .frame(width: 6, height: h)
                        .position(x: centre, y: h / 2)
                }

                if let lit = RetailAssets.billboardImage("Art/Sprites/progress-bar-lit.png") {
                    Image(uiImage: lit)
                        .resizable()
                        .interpolation(.medium)
                        .frame(width: lineWidth, height: max(1, cursorTop + cursorH / 2))
                        .frame(height: h, alignment: .top)
                        .clipped()
                        .position(x: centre, y: h / 2)
                }

                Group {
                    if let cursor = RetailAssets.billboardImage("Art/Sprites/progress-cursor.png") {
                        Image(uiImage: cursor)
                            .resizable()
                            .interpolation(.medium)
                    } else {
                        Circle().fill(Palette.gold)
                    }
                }
                .frame(width: cursorH * 43 / 61, height: cursorH)
                .position(x: centre, y: cursorTop + cursorH / 2)
                .animation(.easeOut(duration: 0.25), value: clamped)
            }
        }
    }
}

// MARK: - Parcel gauges

/// "Parcel Collect" and "Parcel Deliver", the two horizontal bars the original
/// prints across the bottom of the race, with the same labels it used. The
/// retail `sliderbar` file is a hollow 256x32 box and `sliderbarfull` the gold
/// that fills it.
private struct ParcelGauges: View {
    let collect: Double
    let deliver: Double
    let scale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            gauge(label: "Parcel Collect", fraction: collect,
                  tint: Color(red: 1.0, green: 0.63, blue: 0.31))
            gauge(label: "Parcel Deliver", fraction: deliver,
                  tint: Color(red: 0.42, green: 0.89, blue: 1.0))
        }
    }

    private func gauge(label: String, fraction: Double, tint: Color) -> some View {
        let clamped = min(1, max(0, fraction))
        let w = 256 * scale
        let h = 32 * scale
        return ZStack(alignment: .leading) {
            if let track = RetailAssets.image("Art/Sprites/sliderbar.png") {
                Image(uiImage: track)
                    .resizable()
                    .interpolation(.medium)
                    .frame(width: w, height: h)
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.black.opacity(0.45))
                    .frame(width: w, height: h)
            }

            GeometryReader { geo in
                Group {
                    if let full = RetailAssets.image("Art/Sprites/sliderbarfull.png") {
                        Image(uiImage: full).resizable().interpolation(.medium)
                    } else {
                        LinearGradient(colors: [tint, tint.opacity(0.6)],
                                       startPoint: .leading, endPoint: .trailing)
                    }
                }
                .frame(width: geo.size.width * clamped, alignment: .leading)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                .clipped()
            }
            .frame(width: w, height: h)

            Text("\(label):\(Int((clamped * 100).rounded()))%")
                .font(.system(size: max(10, 18 * scale), weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.85), radius: 2)
                .frame(width: w, height: h)
        }
        .frame(width: w, height: h)
    }
}

// MARK: - Counters

/// The parcel icon and the number riding with it, in the top-left corner.
private struct ParcelCounter: View {
    let state: RaceState
    let mode: GameMode
    let scale: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 6 * scale) {
            Group {
                if let icon = RetailAssets.billboardImage("Art/Sprites/parcelicon.png") {
                    Image(uiImage: icon).resizable().interpolation(.medium)
                        .aspectRatio(contentMode: .fit)
                } else {
                    ParcelIcon()
                }
            }
            .frame(width: 31 * scale, height: 61 * scale)

            VStack(alignment: .leading, spacing: 2 * scale) {
                Text(state.quota > 0 ? "\(state.parcels)/\(state.quota)" : "\(state.parcels)")
                    .font(.system(size: valueFont, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.gold)
                    .shadow(color: .black.opacity(0.7), radius: 2)

                Text(state.weaponName)
                    .font(.system(size: labelFont, weight: .black, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(Palette.cyan)
                    .shadow(color: .black.opacity(0.7), radius: 2)

                Text(mode.title)
                    .font(.system(size: labelFont - 1, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.ink.opacity(0.75))
            }
            .padding(.top, 4 * scale)
        }
    }

    private var valueFont: CGFloat { max(18, 47 * scale) }
    private var labelFont: CGFloat { max(11, 20 * scale) }
}

/// The snail's remaining lives, bottom-left. The retail file is 32x32 with the
/// snail drawn in rows 6...24.
private struct LifeCounter: View {
    let state: RaceState
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 6 * scale) {
            Group {
                if let icon = RetailAssets.billboardImage("Art/Sprites/life.png") {
                    Image(uiImage: icon).resizable().interpolation(.medium)
                        .aspectRatio(contentMode: .fit)
                } else {
                    Circle().fill(Palette.good)
                }
            }
            .frame(width: 32 * scale, height: 19 * scale)

            Text(String(format: "%.1fs", state.elapsed))
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(Palette.ink.opacity(0.85))
                .shadow(color: .black.opacity(0.7), radius: 2)
        }
    }
}

/// The tutorial's spoken line, shown the way the original showed its prompts:
/// a few centred lines across the top of the road, with the sprite the line is
/// talking about set inline where the retail script put its glyph.
private struct TutorialBanner: View {
    let text: String
    let scale: CGFloat

    /// The retail script's inline-art glyphs, the sprite each stands for and
    /// the word to write instead when the retail art is not installed.
    private static let icons: [Character: (path: String, word: String)] = [
        "{": ("Art/Sprites/parcelicon.png", "package"),
        "}": ("Art/Sprites/mouse.png", "mouse"),
        "~": ("Art/Sprites/particlering-big.png", "power-up"),
        "[": ("Art/Sprites/garbagea.png", "enemy"),
        "]": ("Art/Objects/lazer_lazer.png", "blaster"),
        "^": ("Art/Baked/salt.png", "salt"),
        "_": ("Art/Sprites/health.png", "heart"),
        ";": ("Art/Sprites/particleslow-big.png", "slow ring"),
    ]

    /// A line of the prompt cut into the plain-text runs and the icons between
    /// them, so each piece can be laid out inline.
    private enum Token: Hashable {
        case words(String)
        case icon(Character)
    }

    private var lines: [[Token]] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            var tokens: [Token] = []
            var run = ""
            for ch in line {
                if TutorialBanner.icons[ch] != nil {
                    if !run.isEmpty { tokens.append(.words(run)); run = "" }
                    tokens.append(.icon(ch))
                } else {
                    run.append(ch)
                }
            }
            if !run.isEmpty { tokens.append(.words(run)) }
            return tokens
        }
    }

    private let fontSize: CGFloat = 15

    var body: some View {
        VStack(spacing: 3) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, tokens in
                HStack(spacing: 5) {
                    ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                        switch token {
                        case .words(let s):
                            Text(s)
                                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                                .foregroundStyle(Palette.ink)
                        case .icon(let ch):
                            icon(ch)
                        }
                    }
                }
            }
        }
        .lineLimit(1)
        .shadow(color: .black.opacity(0.85), radius: 3)
        .padding(.horizontal, 16 * max(1, scale))
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.black.opacity(0.42)))
        .overlay(Capsule().stroke(Palette.cyan.opacity(0.6), lineWidth: 1.2))
    }

    @ViewBuilder
    private func icon(_ ch: Character) -> some View {
        if let entry = TutorialBanner.icons[ch], let img = RetailAssets.billboardImage(entry.path) {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .frame(height: fontSize * 1.25)
                .baselineOffset(-2)
        } else if let entry = TutorialBanner.icons[ch] {
            Text(entry.word)
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.ink)
        }
    }
}
