import SpriteKit
import UIKit

/// Every actor and the sky are drawn here from primitives in a single flat,
/// cartoon-neon style: bold dark outlines, saturated fills, a shared palette.
enum Sprites {

    // MARK: - Shared palette

    static let ink      = UIColor(hex: "#2A1440")   // outline
    static let shell    = UIColor(hex: "#8B5CF6")
    static let shellHi  = UIColor(hex: "#C9A6FF")
    static let shellLo  = UIColor(hex: "#5B2E9E")
    static let body     = UIColor(hex: "#F2D9A0")
    static let bodyLo   = UIColor(hex: "#D8B472")
    static let metal    = UIColor(hex: "#8A8FA8")
    static let metalLo  = UIColor(hex: "#5A5F78")
    static let gold     = UIColor(hex: "#FFC64B")
    static let magenta  = UIColor(hex: "#FF3CA6")
    static let cyan     = UIColor(hex: "#58E1FF")
    static let good     = UIColor(hex: "#6BE36B")
    static let danger   = UIColor(hex: "#FF5A6E")

    // MARK: - Helpers

    private static func shape(_ path: CGPath, fill: UIColor, stroke: UIColor = ink,
                              line: CGFloat = 3) -> SKShapeNode {
        let n = SKShapeNode(path: path)
        n.fillColor = fill
        n.strokeColor = stroke
        n.lineWidth = line
        n.lineJoin = .round
        return n
    }

    private static func circle(_ r: CGFloat, _ c: CGPoint, fill: UIColor,
                               stroke: UIColor = ink, line: CGFloat = 3) -> SKShapeNode {
        shape(CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2),
                     transform: nil), fill: fill, stroke: stroke, line: line)
    }

    private static func roundRect(_ w: CGFloat, _ h: CGFloat, _ c: CGPoint,
                                  radius: CGFloat, fill: UIColor,
                                  stroke: UIColor = ink, line: CGFloat = 3) -> SKShapeNode {
        let r = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
        return shape(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius,
                            transform: nil), fill: fill, stroke: stroke, line: line)
    }

    private static func line(from a: CGPoint, to b: CGPoint, width: CGFloat,
                             color: UIColor) -> SKShapeNode {
        let p = CGMutablePath()
        p.move(to: a); p.addLine(to: b)
        let n = SKShapeNode(path: p)
        n.strokeColor = color
        n.lineWidth = width
        n.lineCap = .round
        return n
    }

    // MARK: - Retail artwork

    /// The imported retail sprite for `path`, sized so its artwork spans `width`
    /// world units — or nil when `tools/import_art.py` has not been run and the
    /// art is not in the bundle, which leaves every caller on the procedural
    /// drawing below it.
    ///
    /// `lift` raises the sprite by that fraction of its own height. The flat art
    /// this replaces is centred on the road point, so a billboard meant to stand
    /// on the road passes `0.5` and a flat or floating one passes `0`.
    private static func retail(_ path: String, width: CGFloat,
                               lift: CGFloat = 0.5) -> SKNode? {
        guard RetailAssets.installed, let tex = RetailAssets.billboard(path) else { return nil }
        let size = tex.size()
        guard size.width > 0, size.height > 0 else { return nil }
        let node = SKSpriteNode(texture: tex)
        node.size = CGSize(width: width, height: width * size.height / size.width)
        node.position = CGPoint(x: 0, y: node.size.height * lift)
        return node
    }

    /// A retail billboard kept whole, for art that shares one canvas with its
    /// siblings and carries its scale in the canvas rather than in its own
    /// opaque bounds. Cropping it to those bounds would hand every sibling the
    /// same size.
    private static func baked(_ path: String, width: CGFloat,
                              lift: CGFloat) -> SKNode? {
        guard RetailAssets.installed, let tex = RetailAssets.texture(path) else { return nil }
        let size = tex.size()
        guard size.width > 0, size.height > 0 else { return nil }
        let node = SKSpriteNode(texture: tex)
        node.size = CGSize(width: width, height: width * size.height / size.width)
        node.position = CGPoint(x: 0, y: node.size.height * lift)
        return node
    }

    /// The heavy rock billboards the retail build scatters across the highway.
    /// Four faces ship, and a rock wears the one its pool slot was given, so a
    /// field of them still reads as a field rather than as one stamp. The face
    /// comes from the scene's own seeded stream rather than a system draw,
    /// which would repaint every rock of a course between one run and the next.
    private static func garbagePath(_ face: Int) -> String {
        let faces = ["a", "b", "c", "d"]
        return "Art/Sprites/garbage\(faces[face & 3]).png"
    }

    /// How many faces a rock is drawn from.
    static let rockFaces = 4

    // MARK: - Retail particles

    /// One frame of the build's own particle art, sized so the drawing spans
    /// `width` points. The installer renders every effect at two sizes — a
    /// 256-pixel `-big` and a 32-pixel `-small` — and the two drawing sizes of
    /// each are the same picture, so a caller picks whichever matches how much
    /// of the screen the effect covers. An effect the bitmaps do not carry, or
    /// a run that is not drawing the retail folder at all, falls through to the
    /// remake's own drawing below.
    static func makeParticle(_ name: String, width: CGFloat,
                             alpha: CGFloat = 1) -> SKSpriteNode? {
        let tex = RetailAssets.billboard("Art/Sprites/\(name).png")
            ?? drawnParticle(name)
        guard let tex else { return nil }
        let size = tex.size()
        guard size.width > 0, size.height > 0 else { return nil }
        // Opaque white and not a clear tint: a three-argument initialiser with
        // a see-through colour multiplies the texture away entirely.
        let node = SKSpriteNode(texture: tex, color: .white,
                                size: CGSize(width: width,
                                             height: width * size.height / size.width))
        node.alpha = alpha
        return node
    }

    // MARK: - Drawn effects

    /// The remake's own drawing of one of the build's effects.
    ///
    /// The 2005 build paints each effect as a small bitmap and the scene asks
    /// for it by name, so a run that is not drawing the retail folder reads it
    /// from here instead: a hit still flashes and throws its sparkles, a skid
    /// still smokes, a rocket still trails its exhaust and a slug still leaves
    /// goo. Each effect is drawn from the radius profile its retail bitmap
    /// wears — measured off the 2005 art rather than copied from it — so an
    /// effect lands on the same colours and the same spread without a retail
    /// pixel going into the build.
    private static func drawnParticle(_ name: String) -> SKTexture? {
        switch name {
        case "spark":            return sparkTexture()
        case "smoke", "jet":     return puffTexture()
        case "sluggoo":          return gooTexture()
        case "startail":         return tailTexture()
        case "particleblasters": return blasterTexture()
        default:
            return name.hasPrefix("particleexplode") ? burstTexture() : nil
        }
    }

    /// A transparent square for a drawing that carries its own alpha.
    private static func particleTexture(_ side: CGFloat,
                                        _ draw: (CGContext, CGSize) -> Void) -> SKTexture {
        let size = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return SKTexture(image: renderer.image { ctx in draw(ctx.cgContext, size) })
    }

    /// One stop of a drawn effect's radius: how far out it sits, what colour it
    /// wears there and how opaque it is.
    ///
    /// The stops below are read off the profile of the matching bitmap in the
    /// retail build — the mean colour and mean alpha of each slice of its
    /// radius — which is what keeps the remake's effects on the build's own
    /// orange rather than on an invented one.
    private struct EffectStop {
        let at: CGFloat
        let hex: String
        let alpha: CGFloat
        init(_ at: CGFloat, _ hex: String, _ alpha: CGFloat) {
            self.at = at; self.hex = hex; self.alpha = alpha
        }
    }

    /// Draws an effect from its radius profile, optionally with the angular
    /// structure the original carries: `lobes` points reaching `depth` of the
    /// radius past the valleys between them, which is what turns a round glow
    /// into a sparkle, a splat or a ragged explosion. A `ragged` figure folds a
    /// second, finer set of points into the first, for the torn edge the
    /// build's blast wears. Zero lobes leaves the effect round, as the build's
    /// smoke is.
    private static func radialEffect(_ side: CGFloat, _ stops: [EffectStop],
                                     lobes: Int = 0, depth: CGFloat = 0,
                                     ragged: CGFloat = 0) -> SKTexture {
        particleTexture(side) { cg, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = size.width / 2
            let ramp = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: stops.map {
                                      UIColor(hex: $0.hex).withAlphaComponent($0.alpha).cgColor
                                  } as CFArray,
                                  locations: stops.map { $0.at })!
            if lobes > 0 {
                let shape = CGMutablePath()
                let steps = 288
                for i in 0...steps {
                    let angle = CGFloat(i) / CGFloat(steps) * 2 * .pi
                    var point = abs(cos(CGFloat(lobes) * angle / 2))
                    if ragged > 0 {
                        let torn = abs(cos(CGFloat(lobes * 2) * angle / 2 + 0.7))
                        point = point * (1 - ragged) + ragged * torn
                    }
                    let r = radius * (1 - depth + depth * point)
                    let p = CGPoint(x: c.x + cos(angle) * r, y: c.y + sin(angle) * r)
                    if i == 0 { shape.move(to: p) } else { shape.addLine(to: p) }
                }
                shape.closeSubpath()
                cg.addPath(shape)
                cg.clip()
            }
            cg.drawRadialGradient(ramp, startCenter: c, startRadius: 0,
                                  endCenter: c, endRadius: radius, options: [])
        }
    }

    /// The flash of a hit: a white core running out through yellow and orange
    /// into the build's deep orange, with a ragged edge. Drawn round rather
    /// than spiked, because the build's own blast is a cloudy ball.
    private static func burstTexture() -> SKTexture {
        radialEffect(128, [
            EffectStop(0.00, "#FFFFFC", 1.00),
            EffectStop(0.13, "#FFF9D3", 1.00),
            EffectStop(0.22, "#FFD07F", 0.86),
            EffectStop(0.30, "#FF9224", 0.57),
            EffectStop(0.38, "#FF6A03", 0.34),
            EffectStop(0.46, "#FF5E00", 0.26),
            EffectStop(0.54, "#FF5800", 0.21),
            EffectStop(0.63, "#FF5300", 0.16),
            EffectStop(0.71, "#FF4F00", 0.10),
            EffectStop(0.79, "#FF4C00", 0.06),
            EffectStop(0.88, "#FF4800", 0.03),
            EffectStop(1.00, "#FF4600", 0.00),
        ], lobes: 9, depth: 0.40, ragged: 0.30)
    }

    /// The build's sparkle: a soft white glow pulled out into eight points.
    private static func sparkTexture() -> SKTexture {
        radialEffect(64, [
            EffectStop(0.00, "#FFFFFF", 0.98),
            EffectStop(0.10, "#FFFFFF", 0.86),
            EffectStop(0.21, "#FFFFFF", 0.60),
            EffectStop(0.29, "#FFFFFF", 0.36),
            EffectStop(0.38, "#FFFFFF", 0.20),
            EffectStop(0.46, "#FFFFFF", 0.155),
            EffectStop(0.54, "#FFFFFF", 0.12),
            EffectStop(0.63, "#FFFFFF", 0.07),
            EffectStop(0.72, "#FFFFFF", 0.02),
            EffectStop(1.00, "#FFFFFF", 0.00),
        ], lobes: 8, depth: 0.34)
    }

    /// The build's smoke: a white ball with no hard edge, so it reads as vapour
    /// whether it is scrubbed off the road or blown out of a rocket.
    private static func puffTexture() -> SKTexture {
        radialEffect(64, [
            EffectStop(0.00, "#FFFFFF", 1.00),
            EffectStop(0.40, "#FFFFFF", 0.90),
            EffectStop(0.50, "#FFFFFF", 0.81),
            EffectStop(0.58, "#FFFFFF", 0.70),
            EffectStop(0.67, "#FFFFFF", 0.59),
            EffectStop(0.75, "#FFFFFF", 0.47),
            EffectStop(0.83, "#FFFFFF", 0.36),
            EffectStop(0.92, "#FFFFFF", 0.25),
            EffectStop(1.00, "#FFFFFF", 0.00),
        ])
    }

    /// What a slug leaves where it was shot: an opaque splat in the build's
    /// burnt orange, scorched brown at the middle and brightest at the rim.
    private static func gooTexture() -> SKTexture {
        radialEffect(64, [
            EffectStop(0.000, "#9B4C00", 1.00),
            EffectStop(0.120, "#BC6005", 1.00),
            EffectStop(0.210, "#D16D00", 1.00),
            EffectStop(0.290, "#E2760A", 1.00),
            EffectStop(0.375, "#DC7520", 1.00),
            EffectStop(0.460, "#D47020", 1.00),
            EffectStop(0.540, "#DB6D1C", 1.00),
            EffectStop(0.630, "#DE6D1A", 1.00),
            EffectStop(0.710, "#DF7529", 1.00),
            EffectStop(0.790, "#E8711A", 0.93),
            EffectStop(0.875, "#E95700", 0.55),
            EffectStop(0.950, "#E95700", 0.12),
            EffectStop(1.000, "#E95700", 0.00),
        ], lobes: 7, depth: 0.10)
    }

    /// A gold burst running out of a white-hot core: the build's blaster
    /// flash, four bumps and all.
    private static func blasterTexture() -> SKTexture {
        radialEffect(128, [
            EffectStop(0.000, "#FFFEF1", 1.00),
            EffectStop(0.130, "#FFFDDD", 1.00),
            EffectStop(0.210, "#FFF799", 1.00),
            EffectStop(0.290, "#FFE744", 0.98),
            EffectStop(0.375, "#FFCC2C", 0.88),
            EffectStop(0.460, "#FFB322", 0.61),
            EffectStop(0.540, "#FFA617", 0.34),
            EffectStop(0.630, "#FFA310", 0.18),
            EffectStop(0.710, "#FFA80F", 0.12),
            EffectStop(0.790, "#FFA90F", 0.08),
            EffectStop(0.875, "#FFAB14", 0.05),
            EffectStop(1.000, "#FFAB14", 0.00),
        ], lobes: 4, depth: 0.30)
    }

    /// The white ball the build trails behind a snail that is moving under its
    /// own steam.
    private static func tailTexture() -> SKTexture {
        radialEffect(32, [
            EffectStop(0.00, "#FFFFFF", 0.98),
            EffectStop(0.21, "#FFFFFF", 0.96),
            EffectStop(0.375, "#FFFFFF", 0.87),
            EffectStop(0.540, "#FFFFFF", 0.68),
            EffectStop(0.710, "#FFFFFF", 0.46),
            EffectStop(0.875, "#FFFFFF", 0.30),
            EffectStop(1.000, "#FFFFFF", 0.00),
        ])
    }


    // MARK: - Turbo the snail (seen from behind as it races away)

    static func makeSnail() -> SKNode {
        if let retail = makeRetailSnail() { return retail }
        let root = SKNode()

        // Jetpack tucked behind the shell.
        root.addChild(roundRect(40, 46, CGPoint(x: 0, y: -22), radius: 10,
                                fill: metal, stroke: ink, line: 3))
        root.addChild(line(from: CGPoint(x: -12, y: -40), to: CGPoint(x: -12, y: -52), width: 8, color: metalLo))
        root.addChild(line(from: CGPoint(x: 12, y: -40), to: CGPoint(x: 12, y: -52), width: 8, color: metalLo))
        root.addChild(circle(5, CGPoint(x: 0, y: -6), fill: cyan, stroke: ink, line: 2))

        // Flame, only visible while boosting.
        if let flame = makeFlame() {
            flame.name = "flame"
            flame.position = CGPoint(x: 0, y: -58)
            flame.alpha = 0
            root.addChild(flame)
        }

        // Foot / body.
        let bodyPath = CGMutablePath()
        bodyPath.addEllipse(in: CGRect(x: -60, y: -30, width: 120, height: 64))
        root.addChild(shape(bodyPath, fill: bodyLo, line: 3))
        let bellyPath = CGMutablePath()
        bellyPath.addEllipse(in: CGRect(x: -52, y: -22, width: 104, height: 48))
        root.addChild(shape(bellyPath, fill: body, line: 0))

        // Shell with a spiral.
        root.addChild(circle(40, CGPoint(x: 0, y: 18), fill: shell, stroke: ink, line: 4))
        let spiral = CGMutablePath()
        var radius: CGFloat = 30
        var angle: CGFloat = 0
        spiral.move(to: CGPoint(x: 0, y: 18))
        while radius > 4 {
            angle += 0.9
            radius -= 3.4
            spiral.addLine(to: CGPoint(x: cos(angle) * radius, y: sin(angle) * radius + 18))
        }
        let spiralNode = SKShapeNode(path: spiral)
        spiralNode.strokeColor = shellHi
        spiralNode.lineWidth = 5
        spiralNode.lineCap = .round
        root.addChild(spiralNode)
        root.addChild(circle(9, CGPoint(x: -14, y: 34), fill: shellHi.withAlphaComponent(0.7), stroke: .clear, line: 0))

        // Eye stalks peeking over the shell.
        for sgn in [-1.0, 1.0] as [CGFloat] {
            root.addChild(line(from: CGPoint(x: sgn * 12, y: 48),
                               to: CGPoint(x: sgn * 22, y: 74), width: 7, color: body))
            root.addChild(circle(9, CGPoint(x: sgn * 22, y: 76), fill: .white, stroke: ink, line: 3))
            root.addChild(circle(4, CGPoint(x: sgn * 22 + sgn * 2, y: 77), fill: ink, stroke: .clear, line: 0))
        }

        return root
    }

    /// Turbo himself: the billboards baked out of the retail build's own
    /// `snail-turbo` meshes, with the procedural exhaust plume kept because it
    /// reads better than the model's flat thrust texture.
    private static func makeRetailSnail() -> SKNode? {
        guard let body = SnailFrames(width: snailFrameWidth) else { return nil }
        body.name = "snailframes"
        let root = SKNode()
        root.addChild(body)
        if let gear = SnailGear(matching: body) {
            gear.name = "snailgear"
            root.addChild(gear)
        }
        if let flame = makeFlame() {
            flame.name = "flame"
            // Just below Turbo's own middle, where the trimmed billboard put it.
            flame.position = CGPoint(x: 0,
                                     y: body.size.height * snailFrameArtHeight / 2 - 4)
            flame.alpha = 0
            root.addChild(flame)
        }
        return root
    }

    /// Drives the weapon, jetpack and invincibility bubble the retail build
    /// bolts onto Turbo. `weapon` is the shot mesh the ladder rung picked, one
    /// to three. A snail drawn procedurally has no gear node, so this does
    /// nothing there rather than half-drawing the add-ons.
    static func setSnailGear(_ node: SKNode, weapon: Int, jetpack: Bool,
                             invincible: Bool, dt: CGFloat) {
        guard let gear = node.childNode(withName: "snailgear") as? SnailGear else { return }
        gear.update(weapon: weapon, jetpack: jetpack, invincible: invincible, dt: dt)
        // The pack burns its own plume, so the drawn flame stands down for it.
        node.childNode(withName: "flame")?.isHidden = jetpack
    }

    // MARK: - Turbo's animation

    /// One clip out of the retail build's `X/ANIMATION.TXT`: the poses it swaps
    /// between, how long the whole run takes, and whether it plays once through
    /// or bounces back and forth forever.
    struct SnailClip {
        let frames: [Int]
        let seconds: CGFloat
        let pingPong: Bool
    }

    /// Every clip the retail build animates Turbo with, transcribed from
    /// `X/ANIMATION.TXT` — the frame numbers in play order, the duration, and
    /// the `Mode:` line. The comment above each is the script's own.
    static let snailClips: [String: SnailClip] = [
        // "Standing still"
        "base":       SnailClip(frames: [0], seconds: 0.5, pingPong: false),
        "invincible": SnailClip(frames: [0], seconds: 0.5, pingPong: false),
        // "Scootin' Along"
        "move":       SnailClip(frames: [0, 1], seconds: 0.5, pingPong: true),
        // "Alternative Move with Bobbing Head"
        "bobalong":   SnailClip(frames: [0, 1, 2, 3, 4], seconds: 0.5, pingPong: true),
        // "Bumped into Something Painful"
        "damaged":    SnailClip(frames: [0, 1], seconds: 0.3, pingPong: true),
        // "Falling to his snaily death": one wind-up, then eleven of the plunge.
        "fall":       SnailClip(frames: [0] + Array(repeating: 1, count: 11),
                                seconds: 6, pingPong: false),
        // "A look backwards used occasionally during big jumps". The script
        // lists the turn out and back, so this one plays through.
        "lookbackleft":  SnailClip(frames: [0, 1, 2, 3, 4, 4, 4, 3, 2, 1, 0],
                                   seconds: 1.0, pingPong: false),
        "lookbackright": SnailClip(frames: [0, 1, 2, 3, 4, 4, 4, 3, 2, 1, 0],
                                   seconds: 1.0, pingPong: false),
        // "Intro Chatty Snail"
        "talk":       SnailClip(frames: Array(0...12), seconds: 3.0, pingPong: false),
        // "Skid to Stop": Turbo scrubs the gear change, wobbles on the spot,
        // then settles.
        "skidstop":   SnailClip(frames: [0, 1, 2, 3, 4, 5, 8, 10,
                                         12, 13, 12, 13, 12, 13, 12, 13,
                                         14, 15, 16, 17, 18],
                                seconds: 2.0, pingPong: false),
        // "Slug Hit Into Shell"
        "intoshell":  SnailClip(frames: Array(0...7), seconds: 1.0, pingPong: false),
    ]

    /// How wide Turbo's own art is, in the same world units the procedural
    /// parts use. Callers that place him in a perspective scene (the race)
    /// divide their target width by this to get the node's scale.
    static let snailNativeWidth: CGFloat = 116

    /// Turbo's share of one animation frame, in the frame's own pixels: the
    /// `turbo-base` pose's opaque box is 137 of the frame's 384 pixels across
    /// and 252 tall, its feet resting on row 357.2.
    fileprivate static let snailFrameArtWidth: CGFloat = 137.0 / 384.0
    fileprivate static let snailFrameArtHeight: CGFloat = 252.0 / 384.0
    fileprivate static let snailFrameFeet: CGFloat = 357.2 / 384.0

    /// The width an animation frame is drawn at. `bake_clips` stores the poses
    /// whole inside one shared window rather than trimming each one, so the node
    /// is sized to the window; this width makes the Turbo inside it come out
    /// exactly as wide as the trimmed `snail.png` billboard drew him (that one
    /// puts the same pose across 148 of its 152 pixels).
    static let snailFrameWidth: CGFloat =
        snailNativeWidth * (148.0 / 152.0) / snailFrameArtWidth

    /// How wide Turbo stands in the engine's own units — the `turbo-base` mesh
    /// runs x -0.303...0.302 — which are the units the road is nine across in.
    /// Sizing him against the highway with this keeps the proportion the build
    /// modelled him at, where a share of the screen would not.
    static let snailModelWidth: CGFloat = 0.606

    /// Advance Turbo's animation by `dt` seconds while it plays `clip`. Asking
    /// for the clip already playing just carries it on, so a caller can name its
    /// clip every frame; a clip the art does not ship, and the procedural snail,
    /// which has no frames at all, are both left alone.
    static func setSnailClip(_ node: SKNode, _ clip: String, dt: CGFloat) {
        (node.childNode(withName: "snailframes") as? SnailFrames)?.play(clip, dt: dt)
    }

    private static func makeFlame() -> SKNode? {
        let root = SKNode()
        let outer = CGMutablePath()
        outer.move(to: CGPoint(x: 0, y: -30))
        outer.addQuadCurve(to: CGPoint(x: 0, y: 20), control: CGPoint(x: -20, y: -6))
        outer.addQuadCurve(to: CGPoint(x: 0, y: -30), control: CGPoint(x: 20, y: -6))
        root.addChild(shape(outer, fill: UIColor(hex: "#FF7A2D"), stroke: .clear, line: 0))
        let inner = CGMutablePath()
        inner.move(to: CGPoint(x: 0, y: -22))
        inner.addQuadCurve(to: CGPoint(x: 0, y: 8), control: CGPoint(x: -10, y: -6))
        inner.addQuadCurve(to: CGPoint(x: 0, y: -22), control: CGPoint(x: 10, y: -6))
        root.addChild(shape(inner, fill: UIColor(hex: "#FFD24C"), stroke: .clear, line: 0))
        root.run(.repeatForever(.sequence([
            .scaleY(to: 1.25, duration: 0.09),
            .scaleY(to: 0.8, duration: 0.09),
        ])))
        return root
    }

    static func setBoost(_ node: SKNode, on: Bool) {
        guard let flame = node.childNode(withName: "flame") else { return }
        flame.alpha = on ? 0.95 : 0
    }

    // MARK: - Entities

    static func makeEntity(_ kind: EntityKind, fringe: UIColor, tier: Int = 0,
                           face: Int = 0) -> SKNode {
        let body = makeEntityBody(kind, fringe: fringe, tier: tier, face: face)
        guard groundKinds.contains(kind) else { return body }
        // A soft contact shadow so road objects read as sitting on the track
        // instead of floating. It scales with the sprite, so it stays correct
        // at every depth.
        let root = SKNode()
        // The shadow follows the drawn width, so a big pillar of a cage keeps
        // its own footprint on the road rather than the slim post's. It hangs a
        // fixed share of the node's own width below the road point, which is
        // where the art's base lands, because every body is built at its
        // `entityBaseWidth`.
        let w = entityFootprint(kind, tier: tier)
        let drop = entityBaseWidth(kind) * 0.18
        let shadow = SKShapeNode(ellipseOf: CGSize(width: w * 0.95, height: w * 0.30))
        shadow.fillColor = UIColor.black.withAlphaComponent(0.32)
        shadow.strokeColor = .clear
        shadow.zPosition = -1
        shadow.position = CGPoint(x: 0, y: -drop)
        root.addChild(shadow)
        root.addChild(body)
        return root
    }

    /// Kinds that sit on the road and therefore want a contact shadow.
    private static let groundKinds: Set<EntityKind> = [
        .parcel, .salt, .asteroid, .slug, .turret, .heart,
        .barrier, .enemy, .ramp, .trampoline, .jetpack
    ]

    private static func makeEntityBody(_ kind: EntityKind, fringe: UIColor, tier: Int,
                                       face: Int) -> SKNode {
        if let retail = makeRetailEntity(kind, tier: tier, face: face) { return retail }
        switch kind {
        case .parcel:      return makeParcel()
        case .salt:        return makeSalt()
        case .heart:       return makeHeart()
        case .asteroid:    return makeAsteroid()
        case .slug:        return makeSlug()
        case .turret:      return makePillar(tier: tier)
        case .postOffice:  return makePostOffice()
        case .ringUpgrade: return makeRing(color: good)
        case .ringSlow:    return makeRing(color: UIColor(hex: "#7A5CFF"))
        case .ringExplode: return makeRing(color: gold)
        case .ringNormal:  return makeRing(color: UIColor(hex: "#EAF2FF"))
        case .arch:        return makeArch()
        case .hole:        return makeHole()
        case .barrier:     return makeBarrier()
        case .enemy:       return makeEnemy()
        case .ramp:        return makeRamp()
        case .trampoline:  return makeTrampoline()
        case .jetpack:     return makeJetpackPickup()
        case .signBang:         return makeSignBang()
        case .signConstruction: return makeSignConstruction()
        case .signStop:         return makeSignStop()
        }
    }

    /// The retail billboard for a road entity, or nil to fall back to the flat
    /// drawing. Each sprite is drawn at the width the renderer scales
    /// `entityModelWidth` against, so it covers the stretch of road its mesh did.
    ///
    /// `lift` is where the model's own base sits in the art. The build models
    /// everything in one space whose y = 0 is the road surface — the lazer
    /// object is a flat quad there, the trampoline lies at y 0.03, and the sign
    /// boards float a unit up — so an entity whose own base is off that line has
    /// to be raised off the road point by the difference. `tools/bake_meshes.py`
    /// rasterises each model to its own projected bounds, which makes the lift
    /// `0.5 + pmin / span` of the model's projected bottom `pmin` and height
    /// `span`; the values below are that fraction for each mesh.
    private static func makeRetailEntity(_ kind: EntityKind, tier: Int, face: Int) -> SKNode? {
        let w = entityBaseWidth(kind)
        switch kind {
        case .parcel:
            return retail("Art/Sprites/parcel000.png", width: w)
        case .salt:
            // salt.x: bottom 0.401 of its 1.427-unit height below the road.
            return retail("Art/Baked/salt.png", width: w, lift: 0.219)
        case .heart:
            return retail("Art/Sprites/health.png", width: w)
        case .asteroid:
            return retail(garbagePath(face), width: w)
        case .enemy:
            return retail(garbagePath(face), width: w)
        case .slug:
            return retail("Art/Sprites/slug000.png", width: w)
        case .turret:
            // The whole shared window rather than the post drawn inside it:
            // every tier is baked into the same 8.6 units, so drawing the
            // window at those 8.6 units of road lets each mesh's own width
            // decide how far across the road its post reaches.
            return baked("Art/Baked/pillar-\(clampPillarTier(tier)).png",
                         width: w, lift: pillarCanvasLift)
        case .postOffice:
            // postofficestop.x: a 5.957-unit front standing 0.297 above the road.
            return retail("Art/Baked/postoffice.png", width: w, lift: 0.550)
        case .ringUpgrade, .ringNormal:
            return retail("Art/Sprites/particlering-big.png", width: w)
        case .ringSlow:
            return retail("Art/Sprites/particleslow-big.png", width: w)
        case .ringExplode:
            return retail("Art/Sprites/particleexplode-big.png", width: w)
        case .arch:
            guard let ring = retail("Art/Sprites/particlering-big.png", width: w) else { return nil }
            ring.alpha = 0.45
            return ring
        case .hole:
            return retail("Art/Objects/hole.png", width: w, lift: 0)
        case .ramp:
            return retail("Art/Objects/ramp.png", width: w)
        case .trampoline:
            // tramp.x: a flat mat lying on the road, so its own centre is the
            // road point and its near edge is drawn below it.
            return retail("Art/Baked/tramp.png", width: w, lift: 0)
        case .jetpack:
            return retail("Art/Sprites/jetpack000.png", width: w)
        case .signBang:
            // signbang.x: two 1.94 panels held 1.03...2.97 units over the road.
            return retail("Art/Baked/signbang.png", width: w, lift: 1.031)
        case .signConstruction:
            // signconstruction.x: a 12-unit hoarding standing from y 1.
            return retail("Art/Baked/signconstruction.png", width: w, lift: 0.583)
        case .signStop:
            // signstop.x: an octagon straddling the road, y -0.72...1.14.
            return retail("Art/Baked/signstop.png", width: w, lift: 0.112)
        case .barrier:
            return nil     // the retail fence is a tiled road texture, not a sprite
        }
    }

    private static func makeParcel() -> SKNode {
        let root = SKNode()
        root.addChild(roundRect(46, 46, .zero, radius: 5, fill: UIColor(hex: "#B5783C")))
        root.addChild(line(from: CGPoint(x: 0, y: -22), to: CGPoint(x: 0, y: 22), width: 6,
                           color: UIColor(hex: "#7A4C25")))
        root.addChild(line(from: CGPoint(x: -22, y: 0), to: CGPoint(x: 22, y: 0), width: 6,
                           color: UIColor(hex: "#7A4C25")))
        root.addChild(circle(7, CGPoint(x: 12, y: 13), fill: UIColor(hex: "#E23C9B"), stroke: ink, line: 2))
        return root
    }

    private static func makeSalt() -> SKNode {
        let root = SKNode()
        let pts = [CGPoint(x: 0, y: 26), CGPoint(x: 18, y: -6), CGPoint(x: -18, y: -6)]
        let p = CGMutablePath(); p.addLines(between: pts); p.closeSubpath()
        root.addChild(shape(p, fill: UIColor(hex: "#EAF2FF"), line: 3))
        let p2 = CGMutablePath()
        p2.addLines(between: [CGPoint(x: -22, y: 8), CGPoint(x: -6, y: -6), CGPoint(x: -22, y: -20)])
        p2.closeSubpath()
        root.addChild(shape(p2, fill: UIColor(hex: "#CFE0F5"), line: 3))
        let p3 = CGMutablePath()
        p3.addLines(between: [CGPoint(x: 22, y: 6), CGPoint(x: 8, y: -8), CGPoint(x: 22, y: -22)])
        p3.closeSubpath()
        root.addChild(shape(p3, fill: UIColor(hex: "#CFE0F5"), line: 3))
        return root
    }

    private static func makeHeart() -> SKNode {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: -22))
        p.addCurve(to: CGPoint(x: -24, y: 10), control1: CGPoint(x: -14, y: -12), control2: CGPoint(x: -24, y: -2))
        p.addArc(center: CGPoint(x: -12, y: 10), radius: 12, startAngle: .pi, endAngle: 0, clockwise: false)
        p.addArc(center: CGPoint(x: 12, y: 10), radius: 12, startAngle: .pi, endAngle: 0, clockwise: false)
        p.addCurve(to: CGPoint(x: 0, y: -22), control1: CGPoint(x: 24, y: -2), control2: CGPoint(x: 14, y: -12))
        p.closeSubpath()
        return shape(p, fill: UIColor(hex: "#FF4E8A"), line: 3)
    }

    private static func makeAsteroid() -> SKNode {
        let root = SKNode()
        let n = 9
        let p = CGMutablePath()
        for i in 0..<n {
            let a = CGFloat(i) / CGFloat(n) * .pi * 2
            let r = 34 + CGFloat((i * 37) % 10) - 5
            let pt = CGPoint(x: cos(a) * r, y: sin(a) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        root.addChild(shape(p, fill: UIColor(hex: "#4E6FD8"), line: 4))
        root.addChild(circle(8, CGPoint(x: -10, y: 8), fill: UIColor(hex: "#374FA8"), stroke: .clear, line: 0))
        root.addChild(circle(5, CGPoint(x: 12, y: -12), fill: UIColor(hex: "#374FA8"), stroke: .clear, line: 0))
        root.addChild(circle(4, CGPoint(x: 6, y: 16), fill: UIColor(hex: "#6B88E8"), stroke: .clear, line: 0))
        return root
    }

    private static func makeSlug() -> SKNode {
        let root = SKNode()
        root.addChild(circle(22, CGPoint(x: 0, y: 0), fill: UIColor(hex: "#6BC24E"), line: 3))
        root.addChild(line(from: CGPoint(x: -8, y: 18), to: CGPoint(x: -14, y: 32), width: 5, color: UIColor(hex: "#6BC24E")))
        root.addChild(line(from: CGPoint(x: 8, y: 18), to: CGPoint(x: 14, y: 32), width: 5, color: UIColor(hex: "#6BC24E")))
        root.addChild(circle(5, CGPoint(x: -14, y: 34), fill: .white, stroke: ink, line: 2))
        root.addChild(circle(5, CGPoint(x: 14, y: 34), fill: .white, stroke: ink, line: 2))
        root.addChild(circle(2, CGPoint(x: -14, y: 34), fill: ink, stroke: .clear, line: 0))
        root.addChild(circle(2, CGPoint(x: 14, y: 34), fill: ink, stroke: .clear, line: 0))
        return root
    }

    /// The retail build models its turrets as the same post at eight widths
    /// (`X/PILLAR1..8.X2`), which is how a course raises a slim pillar into one
    /// wide enough to block the road. Every tier spans the same height and the
    /// same depth; these are the widths they stand at, straight from the meshes.
    private static let pillarTierSpan: [CGFloat] = [
        1.040, 1.711, 2.739, 3.654, 4.855, 5.826, 6.853, 7.998,
    ]
    /// The window `tools/bake_meshes.py` renders all eight of them inside, in
    /// those same units. Because the window is shared, the post covers
    /// `1.040 / 8.6` of the canvas it is drawn on, which is what lets a post
    /// reach as far across the road as its own mesh did.
    private static let pillarCanvasSpan: CGFloat = 8.6

    /// Where the road runs through that canvas. The window is centred on the
    /// post's projected middle, and the build stands the post with a unit of it
    /// under the road surface, so the road line lies `0.354` of the way up the
    /// canvas. `retail` raises a sprite by the share of its height that falls
    /// below the road line, and the readouts are the same fraction for the art
    /// drawn whole: `0.5 - 1.2545 / 8.6`.
    private static let pillarCanvasLift: CGFloat = 0.3541

    /// A pillar tier outside what the build ships would have no mesh to draw,
    /// so clamp it to the eight there are.
    private static func clampPillarTier(_ tier: Int) -> Int {
        max(1, min(pillarTierSpan.count, tier))
    }

    /// How much wider a pillar of `tier` stands than the slim tier-1 post, as
    /// the ratio of their meshes. The renderer scales the pillar's footprint
    /// and its collision with this, so what is drawn is what the snail hits.
    static func pillarWidthFactor(_ tier: Int) -> CGFloat {
        let t = clampPillarTier(tier)
        return pillarTierSpan[t - 1] / pillarTierSpan[0]
    }

    /// How wide an entity stands in the engine's own units. Everything the
    /// build ships a mesh for is measured from it, so a post reaches as far
    /// across the road as its own mesh did, the trampoline lies as flat as it
    /// was modelled and the post office front spans the width it was built at.
    /// The props that exist only as 2D art keep the width the flat drawing gave
    /// them, a little under a quarter of the road: hearts, rocks, slugs, the
    /// rings, the arch, ramps and parcels.
    static func entityModelWidth(_ kind: EntityKind) -> CGFloat {
        switch kind {
        case .salt:       return 1.212       // salt.x, x -0.495...0.717
        case .turret:     return pillarCanvasSpan
        case .postOffice: return 5.999       // postofficestop.x
        case .trampoline: return 3.0         // tramp.x
        case .jetpack:    return 1.617       // jetpack-base-000.x
        // The build's fence is a nine-unit quad tiled along the road rather
        // than a prop, so the stand-in post is sized to the one cell it marks.
        case .barrier:    return roadModelWidth / 8
        default:          return 2.0
        }
    }

    /// How wide a road entity's contact shadow is drawn, in the same local
    /// units `makeEntity` builds the body in. The renderer scales a whole
    /// entity node by `entityModelWidth / entityBaseWidth`, so a shadow this
    /// wide lands on the road exactly as wide as the art drawn over it. A
    /// turret is drawn as the shared canvas its post sits in, so its shadow is
    /// the post's own share of that canvas rather than the whole of it.
    static func entityFootprint(_ kind: EntityKind, tier: Int) -> CGFloat {
        guard kind == .turret else { return entityBaseWidth(kind) }
        let t = clampPillarTier(tier)
        return entityBaseWidth(.turret) * pillarTierSpan[t - 1] / pillarCanvasSpan
    }

    private static func makePillar(tier: Int) -> SKNode {
        // The stand-in for a checkout without the retail meshes: the flat post
        // from the procedural art, thickening with the tier so the course still
        // reads the way it plays.
        let f = pillarWidthFactor(tier)
        let root = SKNode()
        root.addChild(roundRect(34 * f, 90, CGPoint(x: 0, y: 0), radius: 8, fill: metal, line: 3))
        root.addChild(roundRect(52 * f, 26, CGPoint(x: 0, y: 40), radius: 8, fill: metalLo, line: 3))
        root.addChild(circle(7 * f, CGPoint(x: 0, y: 40), fill: danger, stroke: ink, line: 2))
        return root
    }

    private static func makePostOffice() -> SKNode {
        let root = SKNode()
        root.addChild(roundRect(150, 100, CGPoint(x: 0, y: 0), radius: 12,
                                fill: UIColor(hex: "#E23C9B"), line: 4))
        root.addChild(roundRect(120, 34, CGPoint(x: 0, y: 8), radius: 6,
                                fill: UIColor(hex: "#2A1440"), line: 0))
        root.addChild(roundRect(150, 22, CGPoint(x: 0, y: 62), radius: 10,
                                fill: gold, line: 4))
        // Little flag.
        root.addChild(line(from: CGPoint(x: 52, y: 62), to: CGPoint(x: 52, y: 96), width: 6, color: ink))
        let flag = CGMutablePath()
        flag.addLines(between: [CGPoint(x: 52, y: 96), CGPoint(x: 82, y: 86), CGPoint(x: 52, y: 76)])
        flag.closeSubpath()
        root.addChild(shape(flag, fill: cyan, line: 3))
        return root
    }

    private static func makeRing(color: UIColor) -> SKNode {
        let root = SKNode()
        let ring = SKShapeNode(circleOfRadius: 40)
        ring.fillColor = .clear
        ring.strokeColor = color
        ring.lineWidth = 9
        ring.glowWidth = 4
        root.addChild(ring)
        let inner = circle(30, .zero, fill: color.withAlphaComponent(0.12), stroke: .clear, line: 0)
        root.addChild(inner)
        root.run(.repeatForever(.sequence([
            .scale(to: 1.1, duration: 0.5),
            .scale(to: 0.92, duration: 0.5),
        ])))
        return root
    }

    private static func makeHole() -> SKNode {
        let root = SKNode()
        // Mouth of the pit: a flat black ellipse punched straight through the
        // road surface, sized to the width the snail actually falls through.
        root.addChild(shape(CGPath(ellipseIn: CGRect(x: -60, y: -23, width: 120, height: 46),
                                   transform: nil),
                            fill: UIColor.black.withAlphaComponent(0.95),
                            stroke: UIColor(hex: "#4A2E7A"), line: 3))
        // Inner ellipse shifted toward the far lip reads as depth rather than a
        // painted-on black blob.
        root.addChild(shape(CGPath(ellipseIn: CGRect(x: -42, y: -6, width: 84, height: 28),
                                   transform: nil),
                            fill: UIColor(hex: "#1A0B31").withAlphaComponent(0.85),
                            stroke: .clear, line: 0))
        // A brighter rim so the pit is legible at speed against the tan road.
        root.addChild(shape(CGPath(ellipseIn: CGRect(x: -62, y: -24, width: 124, height: 47),
                                   transform: nil),
                            fill: .clear,
                            stroke: UIColor(hex: "#9C6BFF").withAlphaComponent(0.75), line: 2))
        root.name = "hole"
        return root
    }

    /// A fence post with two rails: the blue highway barrier, the cage pillars
    /// and the rail fences the retail grids place across the road. Solid to the
    /// touch, so it is drawn to read as a hard object rather than a pickup.
    ///
    /// The build paints this out of one eight-pixel texture — a dark-to-bright
    /// blue gradient it stretches along the rail — so the post wears that same
    /// gradient instead of a colour invented for it.
    private static func makeBarrier() -> SKNode {
        let root = SKNode()
        let rail = barrierGradient
        let parts: [(CGFloat, CGFloat, CGPoint, CGFloat)] = [
            (14, 96, .zero, 5),          // the post itself
            (46, 14, CGPoint(x: 0, y: 22), 4),
            (46, 14, CGPoint(x: 0, y: -18), 4),
        ]
        for (w, h, centre, radius) in parts {
            let bar = roundRect(w, h, centre, radius: radius,
                                fill: rail == nil ? cyan : .white,
                                stroke: ink, line: 3)
            bar.fillTexture = rail
            root.addChild(bar)
        }
        return root
    }

    /// The retail `Barrier` texture — eight pixels of dark-to-bright blue the
    /// build tiles over a rail — stretched into a strip a drawn bar can wear.
    ///
    /// The rail the levels stand at the road edge wears the same strip: the
    /// build's fence is a quad that maps this texture's height over the rail's
    /// own height and its width along the road, where every column is the same
    /// colour, so the gradient runs up the rail and nothing repeats down it.
    static let barrierGradient: SKTexture? = {
        guard RetailAssets.installed,
              let img = RetailAssets.image("Art/Objects/barrier_barrier.png") else { return nil }
        let strip = CGSize(width: img.size.width, height: 32)
        let renderer = UIGraphicsImageRenderer(size: strip)
        let out = renderer.image { _ in
            img.draw(in: CGRect(origin: .zero, size: strip))
        }
        return SKTexture(image: out)
    }()

    /// The "evil" the tutorial warns about: a spiky pest that rams the snail
    /// off the highway. Angular dark spikes and a hot magenta core make it read
    /// as hostile next to the round, friendly pickups.
    private static func makeEnemy() -> SKNode {
        let root = SKNode()
        let spikes = 8
        let p = CGMutablePath()
        for i in 0..<(spikes * 2) {
            let a = CGFloat(i) / CGFloat(spikes * 2) * .pi * 2
            let r: CGFloat = i % 2 == 0 ? 40 : 22
            let pt = CGPoint(x: cos(a) * r, y: sin(a) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        root.addChild(shape(p, fill: UIColor(hex: "#8A1B52"), line: 4))
        root.addChild(circle(15, .zero, fill: magenta, line: 3))
        root.addChild(circle(5, CGPoint(x: -5, y: 3), fill: ink, stroke: .clear, line: 0))
        root.addChild(circle(5, CGPoint(x: 5, y: 3), fill: ink, stroke: .clear, line: 0))
        return root
    }

    /// A launch ramp: a gold wedge with a bright chevron, so the player reads
    /// "hit this to fly" at a glance.
    private static func makeRamp() -> SKNode {
        let root = SKNode()
        let p = CGMutablePath()
        p.addLines(between: [CGPoint(x: -44, y: -22), CGPoint(x: 44, y: -22), CGPoint(x: 0, y: 34)])
        p.closeSubpath()
        root.addChild(shape(p, fill: gold, line: 4))
        for dy in [CGFloat(0), -16] {
            let chevron = CGMutablePath()
            chevron.addLines(between: [CGPoint(x: -18, y: -4 + dy),
                                       CGPoint(x: 0, y: 12 + dy),
                                       CGPoint(x: 18, y: -4 + dy)])
            let n = SKShapeNode(path: chevron)
            n.strokeColor = ink
            n.lineWidth = 5
            n.lineCap = .round
            root.addChild(n)
        }
        return root
    }

    /// A trampoline pad: a stretchy cyan deck on a coil, the springier cousin
    /// of the ramp.
    private static func makeTrampoline() -> SKNode {
        let root = SKNode()
        for i in 0..<3 {
            let w = 52 - CGFloat(i) * 14
            root.addChild(shape(CGPath(ellipseIn: CGRect(x: -w / 2, y: -26 + CGFloat(i) * 8,
                                                         width: w, height: 16), transform: nil),
                                fill: metalLo, line: 2))
        }
        root.addChild(roundRect(76, 18, CGPoint(x: 0, y: 6), radius: 9, fill: cyan, line: 3))
        root.addChild(line(from: CGPoint(x: -20, y: 6), to: CGPoint(x: 20, y: 6), width: 3,
                           color: .white.withAlphaComponent(0.7)))
        return root
    }

    /// The jetpack pickup: a stubby pack with a live exhaust, matching the one
    /// already strapped to Turbo.
    private static func makeJetpackPickup() -> SKNode {
        let root = SKNode()
        root.addChild(roundRect(46, 52, CGPoint(x: 0, y: 0), radius: 10, fill: metal, line: 3))
        root.addChild(roundRect(24, 30, CGPoint(x: 0, y: 2), radius: 6, fill: metalLo, line: 2))
        for sgn in [-1.0, 1.0] as [CGFloat] {
            root.addChild(line(from: CGPoint(x: sgn * 15, y: -26), to: CGPoint(x: sgn * 15, y: -40),
                               width: 8, color: metalLo))
            root.addChild(circle(6, CGPoint(x: sgn * 15, y: -44), fill: gold, stroke: ink, line: 2))
        }
        return root
    }

    /// A decorative arch — the `Ring=None` rows. It hangs over the road and does
    /// nothing, so it is drawn faint and does not pulse like a live pickup.
    private static func makeArch() -> SKNode {
        let root = SKNode()
        let ring = SKShapeNode(circleOfRadius: 40)
        ring.fillColor = .clear
        ring.strokeColor = UIColor(hex: "#CFB8FF").withAlphaComponent(0.5)
        ring.lineWidth = 6
        root.addChild(ring)
        return root
    }

    // MARK: - Roadside signs (the `3DModel=` rows)

    /// The warning board a piece hangs either side of it (`signBang.x`): the
    /// retail model is two square panels at x ±3, centred 2 units up, so the
    /// remake draws the same pair of gold panels in the model's own units.
    private static func makeSignBang() -> SKNode {
        let root = SKNode()
        for side in [CGFloat(-1), 1] {
            let panel = SKNode()
            panel.position = CGPoint(x: side * 3.0, y: 2.0)
            panel.addChild(roundRect(1.94, 1.94, .zero, radius: 0.24,
                                     fill: gold, line: 0.18))
            // The "bang": a tapered bar over a dot, the universal warning mark.
            panel.addChild(roundRect(0.40, 1.02, CGPoint(x: 0, y: 0.30), radius: 0.20,
                                     fill: ink, stroke: .clear, line: 0))
            panel.addChild(circle(0.26, CGPoint(x: 0, y: -0.52), fill: ink,
                                  stroke: .clear, line: 0))
            root.addChild(panel)
        }
        return root
    }

    /// The roadworks hoarding (`signConstruction.x`): the model is a single
    /// board 12 across and 12 tall, floating a unit above the road, so it is
    /// drawn as a wide wall of hazard stripes.
    private static func makeSignConstruction() -> SKNode {
        let root = SKNode()
        let board = CGRect(x: -6, y: 1, width: 12, height: 12)
        root.addChild(shape(CGPath(roundedRect: board, cornerWidth: 0.4, cornerHeight: 0.4,
                                   transform: nil),
                            fill: .white, stroke: ink, line: 0.22))
        // Slanted stripes, clipped to the board so they break cleanly at its
        // edge instead of spilling past the frame.
        let stripes = SKCropNode()
        let mask = SKShapeNode(path: CGPath(roundedRect: board.insetBy(dx: 0.3, dy: 0.3),
                                            cornerWidth: 0.2, cornerHeight: 0.2,
                                            transform: nil))
        mask.fillColor = .white
        mask.strokeColor = .clear
        stripes.maskNode = mask
        for i in stride(from: -11, through: 12, by: 3) {
            let x = CGFloat(i)
            let p = CGMutablePath()
            p.addLines(between: [CGPoint(x: x, y: 0.6), CGPoint(x: x + 1.5, y: 0.6),
                                 CGPoint(x: x + 1.5 - 13, y: 13.4), CGPoint(x: x - 13, y: 13.4)])
            p.closeSubpath()
            stripes.addChild(shape(p, fill: UIColor(hex: "#FF7A2D"), stroke: .clear, line: 0))
        }
        root.addChild(stripes)
        return root
    }

    /// The stop sign (`signStop.x`): one small octagon, the only sign the
    /// shipped pieces never actually place.
    private static func makeSignStop() -> SKNode {
        let root = SKNode()
        let centre = CGPoint(x: 0, y: 0.21), r: CGFloat = 1.03
        root.addChild(shape(octagon(centre: centre, r: r), fill: danger, line: 0.16))
        root.addChild(shape(octagon(centre: centre, r: r * 0.74),
                            fill: .clear, stroke: .white, line: 0.12))
        root.addChild(roundRect(1.24, 0.34, centre, radius: 0.10,
                                fill: .white, stroke: .clear, line: 0))
        return root
    }

    private static func octagon(centre: CGPoint, r: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<8 {
            let a = CGFloat.pi / 8 + CGFloat(i) * .pi / 4
            let p = CGPoint(x: centre.x + r * cos(a), y: centre.y + r * sin(a))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    // MARK: - Projectiles

    /// The three shot meshes the ladder's own mask picks between at `0x43a2e0`:
    /// the blaster's pellet, the laser's glowing bolt, then the rocket. The
    /// rocket gets a nose cone, tail fins and an exhaust plume so it is
    /// unmistakable at a glance, and the laser a cyan beam so the middle mesh
    /// reads differently from the pellet.
    static func makeBullet(level: Int) -> SKNode {
        if let retail = makeRetailBullet(level: level) { return retail }
        if level >= 3 {
            let root = SKNode()

            // Exhaust plume trailing the tail.
            let plume = CGMutablePath()
            plume.move(to: CGPoint(x: -14, y: 6))
            plume.addQuadCurve(to: CGPoint(x: -14, y: -6), control: CGPoint(x: -34, y: 0))
            plume.closeSubpath()
            root.addChild(shape(plume, fill: UIColor(hex: "#FF7A2D"), stroke: .clear, line: 0))
            let core = CGMutablePath()
            core.move(to: CGPoint(x: -14, y: 3))
            core.addQuadCurve(to: CGPoint(x: -14, y: -3), control: CGPoint(x: -24, y: 0))
            core.closeSubpath()
            root.addChild(shape(core, fill: UIColor(hex: "#FFD24C"), stroke: .clear, line: 0))

            // Tail fins.
            let fin = CGMutablePath()
            fin.move(to: CGPoint(x: -14, y: 5))
            fin.addLine(to: CGPoint(x: -22, y: 12))
            fin.addLine(to: CGPoint(x: -8, y: 6))
            fin.closeSubpath()
            root.addChild(shape(fin, fill: magenta, line: 2))
            let fin2 = CGMutablePath()
            fin2.move(to: CGPoint(x: -14, y: -5))
            fin2.addLine(to: CGPoint(x: -22, y: -12))
            fin2.addLine(to: CGPoint(x: -8, y: -6))
            fin2.closeSubpath()
            root.addChild(shape(fin2, fill: magenta, line: 2))

            // Body + nose cone.
            root.addChild(roundRect(30, 16, CGPoint(x: -1, y: 0), radius: 7, fill: gold, line: 2))
            let nose = CGMutablePath()
            nose.addLines(between: [CGPoint(x: 14, y: 8), CGPoint(x: 28, y: 0), CGPoint(x: 14, y: -8)])
            nose.closeSubpath()
            root.addChild(shape(nose, fill: UIColor(hex: "#FF7A2D"), line: 2))

            // Window porthole.
            root.addChild(circle(3.5, CGPoint(x: 4, y: 0), fill: cyan, stroke: ink, line: 1.5))
            return root
        }
        if level >= 2 {
            // Laser: a cyan beam bolt — a white-hot core inside a soft glow, so
            // it reads as fire, not a rocket, at a glance.
            let root = SKNode()
            root.addChild(roundRect(12, 34, .zero, radius: 6,
                                    fill: cyan.withAlphaComponent(0.35), stroke: .clear, line: 0))
            root.addChild(roundRect(7, 28, .zero, radius: 3.5, fill: cyan,
                                    stroke: UIColor(hex: "#1C6FA8"), line: 2))
            root.addChild(roundRect(3.5, 18, .zero, radius: 1.75, fill: .white,
                                    stroke: .clear, line: 0))
            return root
        }
        return roundRect(22, 8, .zero, radius: 4, fill: UIColor(hex: "#FFE24C"),
                         stroke: UIColor(hex: "#FF9A3D"), line: 2)
    }

    /// The retail shots. The rocket is the build's own `rocket` mesh baked to a
    /// billboard; the laser is its `lazer` sprite. Both are drawn nose-up, so
    /// each is turned a quarter turn inside its node to face down the road the
    /// way the renderer's own rotation expects. The starting blaster keeps its
    /// flat drawing — the build ships no sprite for it.
    private static func makeRetailBullet(level: Int) -> SKNode? {
        let path: String
        let width: CGFloat
        if level >= 3 {
            path = "Art/Baked/rocket.png"
            width = 28
        } else if level >= 2 {
            path = "Art/Objects/lazer_lazer.png"
            width = 11
        } else {
            return nil
        }
        guard RetailAssets.installed, let tex = RetailAssets.billboard(path),
              tex.size().width > 0 else { return nil }
        let sprite = SKSpriteNode(texture: tex)
        sprite.size = CGSize(width: width, height: width * tex.size().height / tex.size().width)
        sprite.zRotation = -.pi / 2
        let root = SKNode()
        root.addChild(sprite)
        return root
    }

    /// The vapour laser a highway pest spits back at the snail. It stays in
    /// the pest's own hostile palette — a magenta bolt around a white-hot core
    /// — so an incoming shot is never mistaken for a friendly pick-up.
    static func makeEnemyBullet() -> SKNode {
        if let retail = retailBullet("Art/Objects/vapourlazer_lazer.png", width: 30) {
            return retail
        }
        let root = SKNode()
        root.addChild(roundRect(46, 18, .zero, radius: 9,
                                fill: magenta.withAlphaComponent(0.28), stroke: .clear, line: 0))
        root.addChild(roundRect(34, 10, .zero, radius: 5,
                                fill: UIColor(hex: "#FF2E88"), stroke: UIColor(hex: "#7A0F3C"), line: 3))
        root.addChild(roundRect(16, 4, .zero, radius: 2, fill: .white, stroke: .clear, line: 0))
        return root
    }

    /// A muzzle-to-target bolt reused for the pests' return fire: a plain
    /// retail sprite centred on its own node.
    private static func retailBullet(_ path: String, width: CGFloat) -> SKNode? {
        guard RetailAssets.installed, let tex = RetailAssets.billboard(path),
              tex.size().width > 0 else { return nil }
        let node = SKSpriteNode(texture: tex)
        node.size = CGSize(width: width, height: width * tex.size().height / tex.size().width)
        return node
    }

    // MARK: - Sky

    /// A vertical-gradient texture built with Core Graphics, used as the sky.
    static func gradientTexture(size: CGSize, colors: [UIColor],
                                locations: [CGFloat]? = nil) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: size)
        let img = renderer.image { ctx in
            let cg = ctx.cgContext
            let cgColors = colors.map { $0.cgColor } as CFArray
            let space = CGColorSpaceCreateDeviceRGB()
            let stops = locations ?? [0, 0.55, 1]
            let grad = CGGradient(colorsSpace: space, colors: cgColors,
                                  locations: stops)!
            cg.drawLinearGradient(grad, start: .zero,
                                  end: CGPoint(x: 0, y: size.height), options: [])
        }
        return SKTexture(image: img)
    }

    /// A soft radial glow used for nebulae behind the road.
    static func radialTexture(size: CGFloat, color: UIColor) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let img = renderer.image { ctx in
            let cg = ctx.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            let grad = CGGradient(colorsSpace: space,
                                  colors: [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray,
                                  locations: [0, 1])!
            let c = CGPoint(x: size / 2, y: size / 2)
            cg.drawRadialGradient(grad, startCenter: c, startRadius: 0,
                                  endCenter: c, endRadius: size / 2, options: [])
        }
        return SKTexture(image: img)
    }

    /// The strip a roadside wall wears: the fringe colour fading out as it
    /// rises, nearly clear at the top and almost solid where it meets the road.
    ///
    /// The retail `Fringe` art is four pixels of white whose alpha climbs that
    /// way, which is what makes the wall glow at its base and dissolve into the
    /// sky above; the remake draws the same ramp itself so the wall reads as a
    /// wall rather than a flat band of colour down each side of the highway.
    static func fringeGradient(_ color: UIColor) -> SKTexture {
        let h: CGFloat = 64
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: h))
        let img = renderer.image { ctx in
            let cg = ctx.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            let grad = CGGradient(colorsSpace: space,
                                  colors: [color.withAlphaComponent(0.04).cgColor,
                                           color.withAlphaComponent(0.55).cgColor,
                                           color.withAlphaComponent(0.96).cgColor] as CFArray,
                                  locations: [0, 0.55, 1])!
            cg.drawLinearGradient(grad, start: .zero,
                                  end: CGPoint(x: 0, y: h), options: [])
        }
        return SKTexture(image: img)
    }

    // MARK: - Base widths (world units the renderer scales against)

    static func entityBaseWidth(_ kind: EntityKind) -> CGFloat {
        switch kind {
        case .postOffice: 240
        case .hole: 120
        case .slug: 70
        case .turret: 80
        case .ringUpgrade, .ringSlow, .ringExplode, .ringNormal, .arch: 88
        case .asteroid: 80
        case .enemy: 76
        case .ramp: 80
        case .trampoline: 84
        case .barrier: 44
        case .signBang, .signConstruction, .signStop:
            CGFloat(SignKind(entity: kind)?.modelWidth ?? 48)
        default: 48
        }
    }
}

/// Turbo's billboard, animated the way the retail build animates him: by
/// swapping between posed meshes. `tools/bake_meshes.py` rasterises every pose
/// into one shared window, so a swap changes his shape without moving him.
final class SnailFrames: SKSpriteNode {

    /// Frame number -> texture, per clip. A pose the installer never shipped is
    /// simply absent, and the clip holds the pose before it instead.
    private let poses: [String: [Int: SKTexture]]
    private var clip = "base"
    private var clock: CGFloat = 0

    /// Nil when the retail art is not in the bundle, so the caller falls back to
    /// the snail it can draw itself.
    init?(width: CGFloat) {
        var loaded: [String: [Int: SKTexture]] = [:]
        for (name, spec) in Sprites.snailClips {
            var frames: [Int: SKTexture] = [:]
            for n in spec.frames where frames[n] == nil {
                let file = String(format: "snail-%@-%03d.png", name, n)
                if let tex = RetailAssets.texture("Art/Baked/\(file)") { frames[n] = tex }
            }
            if !frames.isEmpty { loaded[name] = frames }
        }
        guard let first = loaded["base"]?[0] else { return nil }
        poses = loaded
        let size = first.size()
        // `color:` here is the node's tint at `colorBlendFactor` 1, so it has
        // to be opaque white: a clear tint multiplies every pixel of the
        // texture away and Turbo renders as nothing at all.
        super.init(texture: first, color: .white,
                   size: CGSize(width: width, height: width * size.height / size.width))
        // Every frame carries the whole shared window, so most of the sprite is
        // empty canvas. Anchoring it where Turbo's feet are keeps him sitting on
        // the road the way the trimmed billboard did.
        position = CGPoint(x: 0, y: self.size.height * (Sprites.snailFrameFeet - 0.5))
    }

    required init?(coder: NSCoder) { nil }

    func play(_ name: String, dt: CGFloat) {
        guard Sprites.snailClips[name] != nil, poses[name] != nil else { return }
        if name == clip { clock += dt } else { clip = name; clock = 0 }
        guard let spec = Sprites.snailClips[name], let tex = frame(of: spec) else { return }
        if texture !== tex { texture = tex }
    }

    /// The pose a clip shows at its current clock. `Pingpong` walks the list
    /// forwards and back again for as long as the clip runs; anything else plays
    /// through once and then holds its last pose.
    private func frame(of spec: Sprites.SnailClip) -> SKTexture? {
        let count = spec.frames.count
        guard count > 0, let index = frameIndex(spec) else { return nil }
        return poses[clip]?[spec.frames[min(count - 1, max(0, index))]]
    }

    private func frameIndex(_ spec: Sprites.SnailClip) -> Int? {
        let count = CGFloat(spec.frames.count)
        guard spec.seconds > 0 else { return 0 }
        if spec.pingPong {
            let u = (clock / spec.seconds).truncatingRemainder(dividingBy: 1)
            let step = u < 0.5 ? u * 2 : (1 - u) * 2
            return Int((step * (count - 1)).rounded())
        }
        return Int((clock / spec.seconds) * count)
    }
}

/// The retail build's add-on meshes for Turbo: the weapon riding his shell, the
/// jetpack when he is carrying one, and the bubble the invincibility power-up
/// wraps him in.
///
/// `tools/bake_meshes.py` rasterises each of them inside Turbo's own animation
/// window, so this node only has to copy the pose sprite's frame and lay the
/// parts over him. There is no offset arithmetic here on purpose: the pieces
/// are already in his space, and any hand-tuned placement would drift the
/// moment the framing changed.
final class SnailGear: SKNode {

    /// The parts of each rung of the weapon ladder, keyed by the tier that
    /// shows them. A rung whose art the installer did not ship is simply
    /// absent, and the tier below keeps its place.
    private var tiers: [Int: [SKSpriteNode]] = [:]
    private var pack: SKSpriteNode?
    private var plume: LoopingSprite?
    private var bubble: LoopingSprite?

    /// Nil when none of the gear's art is in the bundle.
    init?(matching frames: SKSpriteNode) {
        super.init()
        let size = frames.size
        guard size.width > 0, size.height > 0 else { return nil }

        func part(_ name: String, depth: CGFloat) -> SKSpriteNode? {
            guard let tex = RetailAssets.texture("Art/Baked/\(name).png") else { return nil }
            // `color:` has to be opaque white or the tint at full blend factor
            // multiplies the texture away and the part renders as nothing.
            let node = SKSpriteNode(texture: tex, color: .white, size: size)
            node.position = frames.position
            node.zPosition = depth
            return node
        }

        // The ladder as the build's own `X/_ANIMATION.TXT` groups it: one
        // blaster barrel on the shell top with a pod either side, then the pair
        // of lasers that replaces the pods, then the rocket launcher on its own.
        let rungs: [(Int, [String])] = [
            (1, ["snail-blaster-top", "snail-blaster-left", "snail-blaster-right"]),
            (2, ["snail-laser-left", "snail-laser-right"]),
            (3, ["snail-rocket"]),
        ]
        for (tier, names) in rungs {
            let parts = names.compactMap { part($0, depth: 1) }
            guard !parts.isEmpty else { continue }
            for node in parts { addChild(node) }
            tiers[tier] = parts
        }

        // The pack straps to his back, so it and its plume sit behind him while
        // the weapon and the bubble close over the top.
        pack = part("snail-jetpack", depth: -3)
        plume = LoopingSprite(matching: frames, depth: -4, seconds: 0.25,
                              names: (0...2).map { "snail-jetpack-thrust-\(Self.frame($0))" })
        bubble = LoopingSprite(matching: frames, depth: 2, seconds: 0.5,
                               names: (0...3).map { "snail-aura-\(Self.frame($0))" })
        if let pack { addChild(pack) }
        if let plume { addChild(plume) }
        if let bubble { addChild(bubble) }

        guard !tiers.isEmpty || pack != nil || plume != nil || bubble != nil else { return nil }
    }

    required init?(coder: NSCoder) { nil }

    private static func frame(_ n: Int) -> String { String(format: "%03d", n) }

    /// Show the shot mesh a ladder rung asked for, and the pack and bubble
    /// while they are live. Anything not asked for is hidden rather than
    /// removed, so a run that cycles through the three meshes pays for the
    /// textures once.
    func update(weapon: Int, jetpack: Bool, invincible: Bool, dt: CGFloat) {
        let rungs = tiers.keys.sorted()
        let wanted = min(max(weapon, 1), 3)
        let tier = rungs.last(where: { $0 <= wanted }) ?? rungs.first
        for (rung, parts) in tiers {
            let showing = rung == tier
            for node in parts { node.isHidden = !showing }
        }
        pack?.isHidden = !jetpack
        plume?.isHidden = !jetpack
        if jetpack { plume?.tick(dt) }
        bubble?.isHidden = !invincible
        if invincible { bubble?.tick(dt) }
    }
}

/// A billboard that cycles through baked frames drawn inside Turbo's own
/// window, so a looping plume or bubble keeps its place on him the way his own
/// clips do.
final class LoopingSprite: SKSpriteNode {
    private let frames: [SKTexture]
    private let seconds: CGFloat
    private var clock: CGFloat = 0

    /// Nil unless at least two of the named frames are in the bundle — a single
    /// frame is not an animation, and the caller is better off hiding the part.
    init?(matching frames: SKSpriteNode, depth: CGFloat, seconds: CGFloat, names: [String]) {
        let loaded = names.compactMap { RetailAssets.texture("Art/Baked/\($0).png") }
        guard loaded.count > 1, let first = loaded.first else { return nil }
        self.frames = loaded
        self.seconds = seconds
        super.init(texture: first, color: .white, size: frames.size)
        position = frames.position
        zPosition = depth
    }

    required init?(coder: NSCoder) { nil }

    func tick(_ dt: CGFloat) {
        clock += dt
        let step = seconds / CGFloat(frames.count)
        guard step > 0 else { return }
        let index = Int(clock / step) % frames.count
        if texture !== frames[index] { texture = frames[index] }
    }
}

extension UIColor {
    convenience init(hex: String) {
        var value: UInt64 = 0
        var string = hex
        if string.hasPrefix("#") { string.removeFirst() }
        Scanner(string: string).scanHexInt64(&value)
        let r = CGFloat((value & 0xFF0000) >> 16) / 255
        let g = CGFloat((value & 0x00FF00) >> 8) / 255
        let b = CGFloat(value & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }

    /// `other` mixed in by `fraction` of the result: 0 keeps this colour, 1
    /// returns `other`. Used to wash a backdrop's own fog colour down into the
    /// deep base tone instead of painting it at full strength.
    func blended(with other: UIColor, fraction: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        guard getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
              other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else { return self }
        let f = max(0, min(1, fraction))
        return UIColor(red: r1 + (r2 - r1) * f, green: g1 + (g2 - g1) * f,
                       blue: b1 + (b2 - b1) * f, alpha: a1 + (a2 - a1) * f)
    }
}
