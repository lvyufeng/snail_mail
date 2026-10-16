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
    let onOptions: () -> Void
    let onEndGame: () -> Void
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

                // The fail-safe's own line, at the place the build draws it:
                // x=0 (centred) and y=200 in the 640x480 frame, in the same
                // font as the results page's headline (`0x445e70`).
                if state.timedOut {
                    Text("Time's Up")
                        .font(.retailFixed(30, weight: .black))
                        .foregroundStyle(Palette.ink)
                        .shadow(color: .black.opacity(0.85), radius: 10)
                        .position(x: geo.size.width / 2, y: geo.size.height * 200 / 480)
                        .transition(.opacity)
                }

                if state.phase == .ready {
                    VStack(spacing: 12) {
                        Text("DRAG to steer * HOLD to fire")
                            .font(.retailFixed(13, weight: .semibold))
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
                    pauseMenu(scale: s)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: state.phase)
        }
    }

    /// The overlay the original opens while the race is held: three entries,
    /// not a bare caption.
    ///
    /// `0x440640` builds them in this order and at these places in the 640x480
    /// frame — `End Game` (0x4a4f34) at y=145, `Options` (0x4a3b60) at y=190
    /// and `Resume` (0x4a4f2c) at y=320 — so the remake keeps the original's
    /// order and its gap above `Resume` rather than tidying them up.
    private func pauseMenu(scale s: CGFloat) -> some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()

            VStack(spacing: 12 * s) {
                Text("PAUSED")
                    .font(.retailFixed(34, weight: .heavy))
                    .tracking(6)
                    .foregroundStyle(Palette.ink)
                    .shadow(color: Palette.cyan.opacity(0.7), radius: 12)
                    .padding(.bottom, 8 * s)

                ArcadeButton(title: "END GAME", tint: Palette.danger, icon: "⌂",
                             action: onEndGame)
                ArcadeButton(title: "OPTIONS", tint: Palette.cyan, icon: "⚙",
                             action: onOptions)

                // The original leaves a gap between the options and `Resume`,
                // which sits where the third sprite is built.
                ArcadeButton(title: "RESUME", tint: Palette.good, icon: "▶",
                             action: onPause)
                    .padding(.top, 14 * s)
            }
            .frame(maxWidth: 280 * s)
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

                PostalMeter(fraction: state.meterFraction, scale: s)
                    // The retail tube runs from y=70 to y=466 of the 640x480
                    // frame, so it stops 14 rows short of the bottom edge
                    // rather than running off it.
                    .frame(width: 64 * s, height: max(1, height - 84 * sy))
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

/// The health gauge: the retail tube down the right edge.
///
/// `0x4411b0` lays three sprites on one another. The whole tube goes down
/// first as the bright wash of `damageguagebright` (0x5b); the tube itself is
/// then laid over it in two pieces that meet at the health line — the washed
/// violet `damageguage` (0x59) above the line and the hot pink
/// `damageguagefull` (0x5a) below it, so the meter drains from the top down.
///
/// The line is the build's own arithmetic. Its 640x480 frame carries the tube
/// from y=70 down 396 rows of artwork, and the line falls `351 - 308 * fraction`
/// rows below the top (0x497650, 0x497654). At the two ends the build stops
/// working the line out: over 0.999 (0x497424) it pins it to row 0, so the tube
/// is all `damageguagefull`, and under 0.01 (0x497298) to the art's last row, so
/// the tube is all `damageguage`.
///
/// Only the wash answers to the health, and only while the meter is nearly
/// full: over a fraction of 0.9 (0x49726c) the build ramps it in at ten times
/// the overshoot (0x497400), and at or under that line it jumps the sprite
/// entirely (0x441219). Once the meter reads full the build also holds the wash
/// at full strength for the beat it spends in its own "just filled" state,
/// which it enters at 0x441168 and leaves at 0x4410c2.
private struct PostalMeter: View {
    let fraction: Double
    let scale: CGFloat

    private var clamped: Double { min(1, max(0, fraction)) }

    /// The strength of the bright wash, or zero where the build skips it.
    private var brightAlpha: Double {
        clamped > 0.9 ? min(1, (clamped - 0.9) * 10) : 0
    }

    /// Where the two tube sprites meet, in the sprite's own rows — 1 is the
    /// first row of the art and 393 its last. A meter over 0.999 (0x497424)
    /// puts the line above the art, so the tube is all `damageguagefull`, and
    /// one under 0.01 (0x497298) puts it below, so the tube is all
    /// `damageguage` — the build's two ends.
    private var splitRow: Double {
        if clamped > 0.999 { return 0 }
        if clamped < 0.01 { return 393 }
        return min(393, max(0, 350 - 308 * clamped))
    }

    var body: some View {
        GeometryReader { geo in
            let h = max(1, geo.size.height)
            let w = 64 * scale
            let split = CGFloat(splitRow)

            ZStack(alignment: .top) {
                if RetailAssets.installed {
                    GaugeTube(sprite: "damageguagebright", scale: scale, height: h)
                        .opacity(brightAlpha)
                        .animation(.easeOut(duration: 0.2), value: brightAlpha)

                    if split > 1 {
                        GaugeTube(sprite: "damageguage", scale: scale, height: h,
                                  rows: 1...split)
                    }
                    if split < 393 {
                        GaugeTube(sprite: "damageguagefull", scale: scale, height: h,
                                  rows: split...393)
                    }
                } else {
                    // Without the art the meter still reads: the same line
                    // between the spent tube and the pink below it, in the two
                    // colours the retail tube files themselves paint — the
                    // washed violet `damageguage` and the hot pink
                    // `damageguagefull` — and at the strength those files carry
                    // them, so the tube stays glass over the sky instead of
                    // turning into a solid bar of colour down the edge.
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(Color(hex: "#89459B").opacity(0.35))
                            .frame(height: h * split / 393)
                        Rectangle()
                            .fill(Color(hex: "#E03A75").opacity(0.51))
                    }
                    .frame(width: w, height: h)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Palette.ink.opacity(0.55), lineWidth: 1.5)
                    )
                }
            }
            .frame(width: w, height: h, alignment: .top)
            // No implicit animation here: `clamped` is republished every frame
            // the race advances, so an `.animation(value:)` would tear down and
            // restart its curve on each of those frames and leave the tube
            // chasing a level it has already moved past. The per-frame update is
            // the smoothing.
        }
    }
}

/// One retail meter sprite, cut to a band of its own rows and held together at
/// any height: the file carries a fixed fitting in rows 1...33 and another in
/// rows 352...393 with a flat run of tube between them, so a tall screen
/// stretches only the run. `rows` names the slice to show, which is how the
/// meter splits the art between its violet and pink halves.
private struct GaugeTube: View {
    let sprite: String
    let scale: CGFloat
    let height: CGFloat
    var rows: ClosedRange<CGFloat> = 1...393

    private var width: CGFloat { 64 * scale }
    private var capTop: CGFloat { 33 * scale }
    private var capBottom: CGFloat { 42 * scale }
    private var run: CGFloat { max(1, height - capTop - capBottom) }

    /// Where a row of the artwork lands once the run has been stretched to
    /// this height.
    private func screenY(_ row: CGFloat) -> CGFloat {
        if row <= 34 { return min(capTop, max(0, (row - 1) / 33 * capTop)) }
        if row <= 352 { return capTop + min(run, max(0, (row - 34) / 318 * run)) }
        return capTop + run + min(capBottom, max(0, (row - 352) / 42 * capBottom))
    }

    var body: some View {
        slice(rows)
    }

    private func slice(_ rows: ClosedRange<CGFloat>) -> some View {
        let top = screenY(rows.lowerBound)
        let cut = max(0.5, screenY(rows.upperBound) - top)
        return stack
            .offset(y: -top)
            .frame(width: width, height: cut, alignment: .top)
            .clipped()
            .offset(y: top)
            .frame(width: width, height: height, alignment: .top)
    }

    private var stack: some View {
        VStack(spacing: 0) {
            piece(1, rows: 33, height: capTop)
            piece(34, rows: 318, height: run)
            piece(352, rows: 42, height: capBottom)
        }
        .frame(width: width, height: height, alignment: .top)
    }

    @ViewBuilder
    private func piece(_ y: Int, rows: Int, height: CGFloat) -> some View {
        if let cut = RetailAssets.band("Art/Sprites/\(sprite).png", y: y, height: rows) {
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
                // The cursor's `clamped` is republished on every frame of the
                // run, so an implicit animation would restart its curve each
                // frame and lag the marker behind the snail by a quarter second.
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
                .font(.retailFixed(max(10, 18 * scale), weight: .heavy))
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
                    .font(.retailFixed(valueFont, weight: .heavy))
                    .foregroundStyle(Palette.gold)
                    .shadow(color: .black.opacity(0.7), radius: 2)

                Text(state.weaponName)
                    .font(.retailFixed(labelFont, weight: .black))
                    .tracking(1)
                    .foregroundStyle(Palette.cyan)
                    .shadow(color: .black.opacity(0.7), radius: 2)

                Text(mode.title)
                    .font(.retailFixed(labelFont - 1, weight: .bold))
                    .foregroundStyle(Palette.ink.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.top, 4 * scale)
        }
    }

    private var valueFont: CGFloat { max(18, 47 * scale) }
    private var labelFont: CGFloat { max(11, 20 * scale) }
}

/// The snail's remaining lives, bottom-left.
///
/// The original kept nine 32x32 `Art/Sprites/Life.tga` slots in a bottom-left
/// row — x = 13 + 24i at y = 430 of its 640x480 frame — and lit one per spare
/// shell in hand, so the row reads as the lives still banked (`0x43aef0` walks
/// the nine sprite pointers at `0x35bb98` and shows the first `lives` of them).
/// A run starts with none: the score pays them out a thousand points at a time.
/// The retail file draws the snail in rows 6...24, hence the 19-point height.
private struct LifeCounter: View {
    let state: RaceState
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 6 * scale) {
            // Slots overlap by eight pixels at the retail pitch, so the icons
            // sit 24 apart while each keeps its own 32-pixel width.
            HStack(spacing: -8 * scale) {
                ForEach(0..<RaceState.maxLives, id: \.self) { slot in
                    Group {
                        if let icon = RetailAssets.billboardImage("Art/Sprites/life.png") {
                            Image(uiImage: icon).resizable().interpolation(.medium)
                                .aspectRatio(contentMode: .fit)
                        } else {
                            Circle().fill(Palette.good)
                        }
                    }
                    .frame(width: 32 * scale, height: 19 * scale)
                    .opacity(slot < state.lives ? 1 : 0)
                }
            }
            .padding(.leading, -2 * scale)

            Text(String(format: "%.1fs", state.elapsed))
                .font(.retailFixed(13, weight: .bold))
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

    /// The retail script's inline-art glyphs and the sprite each stands for. The
    /// bundle's own drawing is preferred; without it `TutorialGlyph` draws the
    /// item, so the entry only has to name the retail sprite.
    private static let icons: [Character: String] = [
        "{": "Art/Sprites/parcelicon.png",
        "}": "Art/Sprites/mouse.png",
        "~": "Art/Sprites/particlering-big.png",
        "[": "Art/Sprites/garbagea.png",
        "]": "Art/Objects/lazer_lazer.png",
        "^": "Art/Baked/salt.png",
        "_": "Art/Sprites/health.png",
        ";": "Art/Sprites/particleslow-big.png",
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
                                .font(.retailFixed(fontSize, weight: .bold))
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
        if let entry = TutorialBanner.icons[ch], let img = RetailAssets.billboardImage(entry) {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .frame(height: fontSize * 1.25)
                .baselineOffset(-2)
        } else {
            // Without the retail sprites the line draws the item itself rather
            // than spelling it out: written as a word the script reads as
            // "Salt salt burns me!" and "Hearts heart restore my Postal", so
            // the banner stands a small drawing in the glyph's place the same
            // way the retail script drops its sprite into the prose.
            TutorialGlyph(glyph: ch)
                .frame(width: fontSize * 1.35, height: fontSize * 1.35)
                .baselineOffset(-3)
        }
    }
}

/// The eight items the tutorial's prose names inline, drawn the flat
/// cartoon-neon way the rest of the remake draws: the same shapes and palette
/// the in-game sprites use, at banner size. Substitutes for the retail sprite
/// when the original art is not installed, so the line reads as a picture
/// rather than as a repeated word.
private struct TutorialGlyph: View {
    let glyph: Character

    private static let ink  = Color(hex: "#2A1440")
    private static let fill = Color(hex: "#F3ECFF")

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let line = max(1, w * 0.07)
            func blob(_ path: Path, _ colour: Color) {
                ctx.fill(path, with: .color(colour))
                ctx.stroke(path, with: .color(TutorialGlyph.ink), lineWidth: line)
            }
            switch glyph {
            case "{":   // the parcel the mail run is about
                let box = Path(roundedRect: CGRect(x: w * 0.1, y: h * 0.22,
                                                   width: w * 0.8, height: h * 0.68),
                               cornerRadius: w * 0.1)
                blob(box, Color(hex: "#B5783C"))
                var cross = Path()
                cross.move(to: CGPoint(x: w * 0.5, y: h * 0.24))
                cross.addLine(to: CGPoint(x: w * 0.5, y: h * 0.88))
                cross.move(to: CGPoint(x: w * 0.12, y: h * 0.5))
                cross.addLine(to: CGPoint(x: w * 0.88, y: h * 0.5))
                ctx.stroke(cross, with: .color(Color(hex: "#7A4C25")),
                           lineWidth: max(1, w * 0.09))
            case "}":   // the mouse the player steers with
                let shell = Path(roundedRect: CGRect(x: w * 0.28, y: h * 0.08,
                                                     width: w * 0.44, height: h * 0.84),
                                 cornerRadius: w * 0.22)
                blob(shell, TutorialGlyph.fill)
                var split = Path()
                split.move(to: CGPoint(x: w * 0.3, y: h * 0.42))
                split.addLine(to: CGPoint(x: w * 0.7, y: h * 0.42))
                ctx.stroke(split, with: .color(TutorialGlyph.ink),
                           lineWidth: max(1, w * 0.07))
                ctx.fill(Path(ellipseIn: CGRect(x: w * 0.44, y: h * 0.2,
                                                width: w * 0.12, height: h * 0.14)),
                         with: .color(Color(hex: "#58E1FF")))
            case "~":   // the power-up ring
                blob(Path(ellipseIn: CGRect(x: w * 0.12, y: h * 0.12,
                                            width: w * 0.76, height: h * 0.76)),
                     TutorialGlyph.fill)
                ctx.fill(Path(ellipseIn: CGRect(x: w * 0.38, y: h * 0.38,
                                                width: w * 0.24, height: h * 0.24)),
                         with: .color(Color(hex: "#241048")))
            case "[":   // the highway pest
                let rock = Path(roundedRect: CGRect(x: w * 0.08, y: h * 0.3,
                                                    width: w * 0.84, height: h * 0.56),
                                cornerRadius: w * 0.26)
                blob(rock, Color(hex: "#8A8FA8"))
            case "]":   // the blaster
                blob(Path(roundedRect: CGRect(x: w * 0.06, y: h * 0.38,
                                              width: w * 0.62, height: h * 0.3),
                          cornerRadius: w * 0.08), Color(hex: "#8A8FA8"))
                blob(Path(roundedRect: CGRect(x: w * 0.58, y: h * 0.44,
                                              width: w * 0.36, height: h * 0.18),
                          cornerRadius: w * 0.06), Color(hex: "#58E1FF"))
            case "^":   // the salt heap that cannot be shot
                var cone = Path()
                cone.move(to: CGPoint(x: w * 0.5, y: h * 0.18))
                cone.addLine(to: CGPoint(x: w * 0.94, y: h * 0.84))
                cone.addLine(to: CGPoint(x: w * 0.06, y: h * 0.84))
                cone.closeSubpath()
                blob(cone, Color(hex: "#F3ECFF"))
            case "_":   // the heart that repairs the meter
                var heart = Path()
                heart.move(to: CGPoint(x: w * 0.5, y: h * 0.88))
                heart.addCurve(to: CGPoint(x: w * 0.08, y: h * 0.38),
                               control1: CGPoint(x: w * 0.28, y: h * 0.7),
                               control2: CGPoint(x: w * 0.08, y: h * 0.52))
                heart.addCurve(to: CGPoint(x: w * 0.5, y: h * 0.28),
                               control1: CGPoint(x: w * 0.08, y: h * 0.12),
                               control2: CGPoint(x: w * 0.4, y: h * 0.1))
                heart.addCurve(to: CGPoint(x: w * 0.92, y: h * 0.38),
                               control1: CGPoint(x: w * 0.6, y: h * 0.1),
                               control2: CGPoint(x: w * 0.92, y: h * 0.12))
                heart.addCurve(to: CGPoint(x: w * 0.5, y: h * 0.88),
                               control1: CGPoint(x: w * 0.92, y: h * 0.52),
                               control2: CGPoint(x: w * 0.72, y: h * 0.7))
                heart.closeSubpath()
                blob(heart, Color(hex: "#FF5A6E"))
            case ";":   // the slow ring that drags the snail down
                blob(Path(ellipseIn: CGRect(x: w * 0.12, y: h * 0.12,
                                            width: w * 0.76, height: h * 0.76)),
                     Color(hex: "#8B5CF6"))
                ctx.fill(Path(ellipseIn: CGRect(x: w * 0.38, y: h * 0.38,
                                                width: w * 0.24, height: h * 0.24)),
                         with: .color(Color(hex: "#241048")))
            default:
                // `Canvas` draws into a `Void` context, so an unhandled glyph
                // is simply nothing rather than an empty view.
                break
            }
        }
    }
}
