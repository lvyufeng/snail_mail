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

    // MARK: - Turbo the snail (seen from behind as it races away)

    static func makeSnail() -> SKNode {
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

    static func makeEntity(_ kind: EntityKind, fringe: UIColor) -> SKNode {
        let body = makeEntityBody(kind, fringe: fringe)
        guard groundKinds.contains(kind) else { return body }
        // A soft contact shadow so road objects read as sitting on the track
        // instead of floating. It scales with the sprite, so it stays correct
        // at every depth.
        let root = SKNode()
        let w = entityBaseWidth(kind)
        let shadow = SKShapeNode(ellipseOf: CGSize(width: w * 0.95, height: w * 0.30))
        shadow.fillColor = UIColor.black.withAlphaComponent(0.32)
        shadow.strokeColor = .clear
        shadow.zPosition = -1
        shadow.position = CGPoint(x: 0, y: -w * 0.18)
        root.addChild(shadow)
        root.addChild(body)
        return root
    }

    /// Kinds that sit on the road and therefore want a contact shadow.
    private static let groundKinds: Set<EntityKind> = [
        .parcel, .salt, .asteroid, .slug, .turret, .heart,
        .barrier, .enemy, .ramp, .trampoline, .jetpack
    ]

    private static func makeEntityBody(_ kind: EntityKind, fringe: UIColor) -> SKNode {
        switch kind {
        case .parcel:      return makeParcel()
        case .salt:        return makeSalt()
        case .heart:       return makeHeart()
        case .asteroid:    return makeAsteroid()
        case .slug:        return makeSlug()
        case .turret:      return makePillar()
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

    private static func makePillar() -> SKNode {
        let root = SKNode()
        root.addChild(roundRect(34, 90, CGPoint(x: 0, y: 0), radius: 8, fill: metal, line: 3))
        root.addChild(roundRect(52, 26, CGPoint(x: 0, y: 40), radius: 8, fill: metalLo, line: 3))
        root.addChild(circle(7, CGPoint(x: 0, y: 40), fill: danger, stroke: ink, line: 2))
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
    private static func makeBarrier() -> SKNode {
        let root = SKNode()
        root.addChild(roundRect(14, 96, CGPoint(x: 0, y: 0), radius: 5, fill: metal, line: 3))
        root.addChild(roundRect(46, 14, CGPoint(x: 0, y: 22), radius: 4, fill: cyan, line: 3))
        root.addChild(roundRect(46, 14, CGPoint(x: 0, y: -18), radius: 4, fill: cyan, line: 3))
        root.addChild(circle(6, CGPoint(x: 0, y: 44), fill: gold, stroke: ink, line: 2))
        return root
    }

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

    /// The three weapons the pickup ladder climbs: the blaster's pellet, the
    /// laser's glowing bolt, then the rocket the ladder tops out at. The rocket
    /// gets a nose cone, tail fins and an exhaust plume so it is unmistakable at
    /// a glance, and the laser a cyan beam so the middle rung reads differently
    /// from the starting pellet.
    static func makeBullet(level: Int) -> SKNode {
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

    /// The vapour laser a highway pest spits back at the snail. It stays in
    /// the pest's own hostile palette — a magenta bolt around a white-hot core
    /// — so an incoming shot is never mistaken for a friendly pick-up.
    static func makeEnemyBullet() -> SKNode {
        let root = SKNode()
        root.addChild(roundRect(46, 18, .zero, radius: 9,
                                fill: magenta.withAlphaComponent(0.28), stroke: .clear, line: 0))
        root.addChild(roundRect(34, 10, .zero, radius: 5,
                                fill: UIColor(hex: "#FF2E88"), stroke: UIColor(hex: "#7A0F3C"), line: 3))
        root.addChild(roundRect(16, 4, .zero, radius: 2, fill: .white, stroke: .clear, line: 0))
        return root
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
}
