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
        .parcel, .salt, .asteroid, .slug, .turret, .heart
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
        case .hole:        return makeHole()
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
        let node = shape(CGPath(ellipseIn: CGRect(x: -60, y: -23, width: 120, height: 46),
                                transform: nil),
                         fill: UIColor.black.withAlphaComponent(0.92),
                         stroke: UIColor(hex: "#4A2E7A"), line: 3)
        node.name = "hole"
        return node
    }

    // MARK: - Projectiles

    static func makeBullet(level: Int) -> SKNode {
        if level >= 3 {
            let root = SKNode()
            root.addChild(roundRect(30, 14, .zero, radius: 6, fill: gold, line: 2))
            let nose = CGMutablePath()
            nose.addLines(between: [CGPoint(x: 15, y: 7), CGPoint(x: 26, y: 0), CGPoint(x: 15, y: -7)])
            nose.closeSubpath()
            root.addChild(shape(nose, fill: UIColor(hex: "#FF7A2D"), line: 2))
            return root
        }
        return roundRect(24, 9, .zero, radius: 4, fill: UIColor(hex: "#FFE24C"),
                         stroke: UIColor(hex: "#FF9A3D"), line: 2)
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
        case .ringUpgrade, .ringSlow, .ringExplode: 88
        case .asteroid: 80
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
