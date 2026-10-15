import SwiftUI

/// One shared art direction for the whole game: a stylised, neon-tinted deep
/// space. Menu, HUD, results and the in-game sky all pull from here so nothing
/// looks like it came from a different product.
enum Palette {
    static let spaceTop    = Color(hex: "#241048")
    static let spaceMid    = Color(hex: "#160A30")
    static let spaceBottom = Color(hex: "#08040F")

    static let nebulaPink = Color(hex: "#7A1E7A")
    static let nebulaBlue = Color(hex: "#1B3B7A")

    static let gold      = Color(hex: "#FFC64B")
    static let goldDeep  = Color(hex: "#FF8A3D")
    static let magenta   = Color(hex: "#FF3CA6")
    static let cyan      = Color(hex: "#58E1FF")
    static let good      = Color(hex: "#6BE36B")
    static let danger    = Color(hex: "#FF5A6E")

    static let ink       = Color(hex: "#F3ECFF")
    static let panelFill = Color(hex: "#150A2E").opacity(0.72)
}

/// Shared deep-space background: gradient, two soft nebulae, a distant ringed
/// planet and a drifting starfield. Used on the menu and mirrored in-game.
struct SpaceBackground: View {
    var showPlanet: Bool = true

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Palette.spaceTop, Palette.spaceMid, Palette.spaceBottom],
                startPoint: .top, endPoint: .bottom
            )

            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                Circle()
                    .fill(RadialGradient(colors: [Palette.nebulaPink.opacity(0.55), .clear],
                                         center: .center, startRadius: 0, endRadius: w * 0.9))
                    .frame(width: w * 1.6, height: w * 1.6)
                    .position(x: w * 0.15, y: h * 0.12)
                    .blur(radius: 40)

                Circle()
                    .fill(RadialGradient(colors: [Palette.nebulaBlue.opacity(0.5), .clear],
                                         center: .center, startRadius: 0, endRadius: w * 0.8))
                    .frame(width: w * 1.4, height: w * 1.4)
                    .position(x: w * 0.95, y: h * 0.42)
                    .blur(radius: 50)

                if showPlanet {
                    PlanetView()
                        .frame(width: w * 0.5)
                        .position(x: w * 0.78, y: h * 0.13)
                }
            }
            .ignoresSafeArea()

            Starfield()
        }
        .ignoresSafeArea()
    }
}

/// The 2005 build's own backdrop for a screen, filling the display, or the
/// shared drawn space when `tools/import_art.py` has not put the art in the
/// bundle. Every menu screen swaps to this so the chrome sits on the real
/// artwork instead of on a remake of it.
struct RetailBackdrop: View {
    /// The retail tile name, e.g. `menubg`, `help`, `splash`.
    var stem: String
    var showPlanet: Bool = true

    var body: some View {
        Group {
            if let img = RetailAssets.stitched(stem)
                ?? RetailAssets.image("Art/Backgrounds/\(stem).png") {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            } else {
                SpaceBackground(showPlanet: showPlanet)
            }
        }
    }
}

/// A simple ringed planet drawn from primitives, matched to the palette.
struct PlanetView: View {
    var body: some View {
        GeometryReader { geo in
            let d = geo.size.width
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: "#6E3FA8"), Color(hex: "#2C1550")],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(
                        Circle().stroke(Color(hex: "#B98CFF").opacity(0.6), lineWidth: 1.5)
                    )
                    .frame(width: d, height: d)
                    .shadow(color: Palette.magenta.opacity(0.5), radius: 24)

                Ellipse()
                    .stroke(Color(hex: "#58E1FF").opacity(0.7), lineWidth: max(2, d * 0.02))
                    .frame(width: d * 1.55, height: d * 0.34)
                    .rotationEffect(.degrees(-18))
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// Cheaper animated starfield shared by every screen.
struct Starfield: View {
    @State private var phase: CGFloat = 0
    private let stars: [(CGFloat, CGFloat, CGFloat, Double)] = (0..<110).map { _ in
        (CGFloat.random(in: 0...1), CGFloat.random(in: 0...1),
         CGFloat.random(in: 0.8...2.6), Double.random(in: 0.25...1))
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                for s in stars {
                    let y = (s.1 + CGFloat(t * 0.02 * s.3)).truncatingRemainder(dividingBy: 1)
                    let tw = 0.65 + 0.35 * sin(t * 2 + Double(s.0) * 10)
                    let rect = CGRect(x: s.0 * size.width, y: y * size.height, width: s.2, height: s.2)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(s.3 * tw)))
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// Rounded, translucent "console panel" with a neon border. The base chrome for
/// every piece of UI.
struct NeonPanel<Content: View>: View {
    var border: Color = Palette.magenta
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Palette.panelFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(border.opacity(0.85), lineWidth: 1.5)
            )
            .shadow(color: border.opacity(0.35), radius: 12)
    }
}

/// The visual of a primary arcade button: neon pill, no system icons so it
/// stays on-style. Kept separate so it can be dropped inside a `NavigationLink`.
struct ArcadeLabel: View {
    let title: String
    var tint: Color = Palette.good
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            if let icon { Text(icon).font(.system(size: 18, weight: .black)) }
            Text(title)
                .font(.retail(22, weight: .heavy))
                .tracking(1)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .foregroundStyle(.white)
        .background(
            Capsule().fill(LinearGradient(colors: [tint, tint.opacity(0.65)],
                                          startPoint: .top, endPoint: .bottom))
        )
        .overlay(Capsule().stroke(.white.opacity(0.65), lineWidth: 1.5))
        .shadow(color: tint.opacity(0.55), radius: 12, y: 4)
    }
}

/// Primary arcade button built from `ArcadeLabel`.
struct ArcadeButton: View {
    let title: String
    var tint: Color = Palette.good
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) { ArcadeLabel(title: title, tint: tint, icon: icon) }
            .buttonStyle(.plain)
    }
}

/// The glyphs the round chrome buttons can show. Drawn as shapes rather than
/// system characters so they read the same weight as the rest of the kit.
enum RoundIcon {
    case sound(on: Bool)
    case pause
    case play
}

/// Small round icon button (mute / pause / play) matching the shared chrome.
struct RoundIconButton: View {
    let icon: RoundIcon
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Canvas { ctx, size in
                let w = size.width, h = size.height
                let white = GraphicsContext.Shading.color(.white)
                switch icon {
                case .sound(let on):
                    var body = Path()
                    body.move(to: CGPoint(x: w * 0.26, y: h * 0.40))
                    body.addLine(to: CGPoint(x: w * 0.40, y: h * 0.40))
                    body.addLine(to: CGPoint(x: w * 0.58, y: h * 0.24))
                    body.addLine(to: CGPoint(x: w * 0.58, y: h * 0.76))
                    body.addLine(to: CGPoint(x: w * 0.40, y: h * 0.60))
                    body.addLine(to: CGPoint(x: w * 0.26, y: h * 0.60))
                    body.closeSubpath()
                    ctx.fill(body, with: white)
                    if on {
                        for r in [0.16, 0.30] as [CGFloat] {
                            var arc = Path()
                            arc.addArc(center: CGPoint(x: w * 0.60, y: h * 0.5),
                                       radius: w * r,
                                       startAngle: .degrees(-55), endAngle: .degrees(55),
                                       clockwise: false)
                            ctx.stroke(arc, with: white,
                                       style: .init(lineWidth: max(1.5, w * 0.055), lineCap: .round))
                        }
                    } else {
                        var cross = Path()
                        cross.move(to: CGPoint(x: w * 0.70, y: h * 0.38))
                        cross.addLine(to: CGPoint(x: w * 0.90, y: h * 0.62))
                        cross.move(to: CGPoint(x: w * 0.90, y: h * 0.38))
                        cross.addLine(to: CGPoint(x: w * 0.70, y: h * 0.62))
                        ctx.stroke(cross, with: white,
                                   style: .init(lineWidth: max(1.5, w * 0.06), lineCap: .round))
                    }
                case .pause:
                    for x in [0.34, 0.56] as [CGFloat] {
                        let bar = Path(roundedRect: CGRect(x: w * x, y: h * 0.30,
                                                           width: w * 0.12, height: h * 0.40),
                                       cornerRadius: w * 0.04)
                        ctx.fill(bar, with: white)
                    }
                case .play:
                    var tri = Path()
                    tri.move(to: CGPoint(x: w * 0.36, y: h * 0.28))
                    tri.addLine(to: CGPoint(x: w * 0.36, y: h * 0.72))
                    tri.addLine(to: CGPoint(x: w * 0.72, y: h * 0.50))
                    tri.closeSubpath()
                    ctx.fill(tri, with: white)
                }
            }
            .frame(width: 42, height: 42)
            .background(Circle().fill(.white.opacity(0.12)))
            .overlay(Circle().stroke(Palette.cyan.opacity(0.8), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

/// Consistent section/stat label used across HUD and results.
struct StatLabel: View {
    let text: String
    var color: Color = Palette.ink.opacity(0.7)

    var body: some View {
        Text(text.uppercased())
            .font(.retail(11, weight: .heavy))
            .tracking(1.5)
            .foregroundStyle(color)
    }
}

/// One of the retail build's stepped percentage rows: a labelled border with a
/// `<` and a `>` button and the `%02i%%` reading sitting between them. The two
/// rows on the Time Trial screen (`Select Speed` 0x4a3788, `Select Difficulty`
/// 0x4a37a4) and the two on Options (`Music Volume` 0x4a3d14, `Sounds Volume`
/// 0x4a3d30) are the same widget — only the label and the reading change.
struct SteppedRow: View {
    let title: String
    let value: String
    var detail: String = ""
    let previous: () -> Void
    let next: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.retail(13, weight: .heavy))
                .foregroundStyle(Palette.ink.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 8)
            StepArrowButton(icon: "<", action: previous)
            VStack(spacing: 0) {
                Text(value)
                    .font(.retail(15, weight: .black))
                    .foregroundStyle(Palette.gold)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.retail(10, weight: .semibold))
                        .foregroundStyle(Palette.ink.opacity(0.55))
                }
            }
            .frame(minWidth: 76)
            StepArrowButton(icon: ">", action: next)
        }
    }
}

/// The row's two arrow buttons. The retail label strings carry their own `>`
/// (`       Select Speed       >`), so the arrows sit inside the row text.
struct StepArrowButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(icon)
                .font(.retail(20, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Palette.cyan.opacity(0.28)))
                .overlay(Circle().stroke(Palette.cyan.opacity(0.8), lineWidth: 1.2))
        }
        .buttonStyle(.plain)
    }
}

/// The game's mascot, drawn with the exact coordinates and palette that
/// `Sprites.makeSnail()` uses in-game, so the menu and the racer are the same
/// character. Canvas keeps it resolution independent.
struct SnailMascot: View {
    var boosted: Bool = true

    private static let ink     = Color(hex: "#2A1440")
    private static let shell   = Color(hex: "#8B5CF6")
    private static let shellHi = Color(hex: "#C9A6FF")
    private static let body    = Color(hex: "#F2D9A0")
    private static let bodyLo  = Color(hex: "#D8B472")
    private static let metal   = Color(hex: "#8A8FA8")
    private static let cyan    = Color(hex: "#58E1FF")

    var body: some View {
        if let img = RetailAssets.billboardImage("Art/Baked/snail.png") {
            Image(uiImage: img).resizable().scaledToFit()
        } else {
            drawn
        }
    }

    private var drawn: some View {
        Canvas { ctx, size in
            let u = min(size.width, size.height) / 200
            let cx = size.width / 2
            let cy = size.height / 2
            // Sprite space has +y pointing up; flip into canvas space.
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: cx + x * u, y: cy - y * u)
            }
            func rectCentered(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                CGRect(x: cx + (x - w / 2) * u, y: cy - (y + h / 2) * u,
                       width: w * u, height: h * u)
            }
            let inkWidth = max(1.5, 3 * u)

            // Jetpack + nozzles.
            let pack = Path(roundedRect: rectCentered(0, -22, 40, 46), cornerRadius: 10 * u)
            ctx.fill(pack, with: .color(Self.metal))
            ctx.stroke(pack, with: .color(Self.ink), lineWidth: inkWidth)
            for sx in [-12.0, 12.0] as [CGFloat] {
                var nozzle = Path()
                nozzle.move(to: pt(sx, -40))
                nozzle.addLine(to: pt(sx, -54))
                ctx.stroke(nozzle, with: .color(Self.ink), style: .init(lineWidth: 8 * u, lineCap: .round))
            }

            // Exhaust flame.
            if boosted {
                var flame = Path()
                flame.move(to: pt(0, -52))
                flame.addQuadCurve(to: pt(0, -96), control: pt(-22, -66))
                flame.addQuadCurve(to: pt(0, -52), control: pt(22, -66))
                ctx.fill(flame, with: .color(Color(hex: "#FF7A2D")))
                var core = Path()
                core.move(to: pt(0, -54))
                core.addQuadCurve(to: pt(0, -84), control: pt(-11, -66))
                core.addQuadCurve(to: pt(0, -54), control: pt(11, -66))
                ctx.fill(core, with: .color(Color(hex: "#FFD24C")))
            }

            // Foot / body.
            let bodyPath = Path(ellipseIn: rectCentered(0, 2, 120, 64))
            ctx.fill(bodyPath, with: .color(Self.bodyLo))
            ctx.stroke(bodyPath, with: .color(Self.ink), lineWidth: inkWidth)
            ctx.fill(Path(ellipseIn: rectCentered(0, 1, 104, 44)), with: .color(Self.body))

            // Shell + spiral.
            let shellRect = CGRect(x: cx - 40 * u, y: cy - 58 * u, width: 80 * u, height: 80 * u)
            ctx.fill(Path(ellipseIn: shellRect), with: .color(Self.shell))
            ctx.stroke(Path(ellipseIn: shellRect), with: .color(Self.ink), lineWidth: 4 * u)
            var spiral = Path()
            var r: CGFloat = 30
            var a: CGFloat = 0
            spiral.move(to: pt(0, 18))
            while r > 4 {
                a += 0.9
                r -= 3.4
                spiral.addLine(to: pt(cos(a) * r, 18 + sin(a) * r))
            }
            ctx.stroke(spiral, with: .color(Self.shellHi),
                       style: .init(lineWidth: 5 * u, lineCap: .round))

            // Eye stalks.
            for sx in [-1.0, 1.0] as [CGFloat] {
                var stalk = Path()
                stalk.move(to: pt(sx * 12, 48))
                stalk.addLine(to: pt(sx * 22, 74))
                ctx.stroke(stalk, with: .color(Self.body), style: .init(lineWidth: 7 * u, lineCap: .round))
                let eye = CGRect(x: cx + (sx * 22 - 9) * u, y: cy - (76 + 9) * u, width: 18 * u, height: 18 * u)
                ctx.fill(Path(ellipseIn: eye), with: .color(.white))
                ctx.stroke(Path(ellipseIn: eye), with: .color(Self.ink), lineWidth: inkWidth)
                let pupil = CGRect(x: cx + (sx * 22 + sx * 2 - 4) * u, y: cy - (77 + 4) * u, width: 8 * u, height: 8 * u)
                ctx.fill(Path(ellipseIn: pupil), with: .color(Self.ink))
            }
        }
    }
}

/// A little delivery parcel, matching the in-game pickup sprite.
struct ParcelIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let box = Path(roundedRect: CGRect(x: w * 0.08, y: h * 0.14, width: w * 0.84, height: h * 0.8),
                           cornerRadius: w * 0.1)
            ctx.fill(box, with: .color(Color(hex: "#B5783C")))
            ctx.stroke(box, with: .color(Color(hex: "#2A1440")), lineWidth: max(1.5, w * 0.07))
            var cross = Path()
            cross.move(to: CGPoint(x: w * 0.5, y: h * 0.16))
            cross.addLine(to: CGPoint(x: w * 0.5, y: h * 0.92))
            cross.move(to: CGPoint(x: w * 0.1, y: h * 0.52))
            cross.addLine(to: CGPoint(x: w * 0.9, y: h * 0.52))
            ctx.stroke(cross, with: .color(Color(hex: "#7A4C25")), lineWidth: max(1.5, w * 0.08))
            let stamp = CGRect(x: w * 0.6, y: h * 0.6, width: w * 0.22, height: h * 0.22)
            ctx.fill(Path(ellipseIn: stamp), with: .color(Color(hex: "#E23C9B")))
        }
    }
}
