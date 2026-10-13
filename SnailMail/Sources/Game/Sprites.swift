import SpriteKit
import UIKit

/// Sprite factory. Wherever possible this uses the original game's artwork
/// (bundled in `Resources/`), so the remake looks like Snail Mail rather than a
/// generic clone. Anything without a shipped texture — the pickup rings and the
/// weapon projectiles — is drawn procedurally in the same palette.
enum Sprites {

    // MARK: - Texture loading

    static func texture(_ name: String) -> SKTexture? {
        guard UIImage(named: name) != nil else { return nil }
        let t = SKTexture(imageNamed: name)
        t.filteringMode = .linear
        return t
    }

    /// A sprite sized so its width equals `width`, preserving the texture's
    /// aspect ratio. The renderer then scales it by distance.
    static func sprite(_ name: String, width: CGFloat, fallback: SKNode) -> SKNode {
        guard let tex = texture(name) else { return fallback }
        let node = SKSpriteNode(texture: tex)
        let size = tex.size()
        let aspect = size.height / max(size.width, 1)
        node.size = CGSize(width: width, height: width * aspect)
        return node
    }

    // MARK: - Turbo the snail

    static func makeSnail() -> SKNode {
        let root = SKNode()
        let body = sprite("snail", width: 108, fallback: proceduralSnail())
        root.addChild(body)

        // Jetpack flame, tucked behind the shell. It only shows while boosting.
        if let thrust = texture("thrust") {
            let flame = SKSpriteNode(texture: thrust)
            flame.size = CGSize(width: 40, height: 40 * thrust.size().height / max(thrust.size().width, 1))
            flame.position = CGPoint(x: -34, y: -14)
            flame.zRotation = .pi / 2
            flame.alpha = 0
            flame.name = "flame"
            flame.run(.repeatForever(.sequence([
                .scaleY(to: 1.25, duration: 0.1),
                .scaleY(to: 0.85, duration: 0.1),
            ])))
            root.addChild(flame)
        }
        return root
    }

    static func setBoost(_ node: SKNode, on: Bool) {
        guard let flame = node.childNode(withName: "flame") else { return }
        flame.alpha = on ? 0.9 : 0
    }

    private static func proceduralSnail() -> SKNode {
        let root = SKNode()
        let shell = SKShapeNode(circleOfRadius: 22)
        shell.fillColor = UIColor(red: 0.62, green: 0.4, blue: 0.85, alpha: 1)
        shell.strokeColor = UIColor(red: 0.36, green: 0.2, blue: 0.55, alpha: 1)
        shell.lineWidth = 3
        root.addChild(shell)
        return root
    }

    // MARK: - Entities

    static func makeEntity(_ kind: EntityKind, fringe: UIColor) -> SKNode {
        let w = entityBaseWidth(kind)
        switch kind {
        case .parcel:      return sprite("parcel", width: w, fallback: fallbackBox(fringe: UIColor(hex: "#C88A3C")))
        case .salt:        return sprite("salt", width: w, fallback: fallbackBox(fringe: UIColor(hex: "#E7ECF5")))
        case .heart:       return sprite("heart", width: w, fallback: fallbackBox(fringe: UIColor(hex: "#FF4E8A")))
        case .asteroid:    return sprite(["rock_a", "rock_b", "rock_c", "rock_d"].randomElement()!, width: w, fallback: fallbackBox(fringe: UIColor(hex: "#4E6FD8")))
        case .slug:        return sprite("slug", width: w, fallback: fallbackBox(fringe: UIColor(hex: "#6BC24E")))
        case .turret:      return sprite("pillar", width: w, fallback: fallbackBox(fringe: UIColor(hex: "#8A8FA8")))
        case .postOffice:  return sprite("postoffice", width: w, fallback: fallbackBox(fringe: UIColor(hex: "#E23C9B")))
        case .ringUpgrade: return makeRing(color: UIColor(hex: "#4CE07A"))
        case .ringSlow:    return makeRing(color: UIColor(hex: "#7A5CFF"))
        case .ringExplode: return makeRing(color: UIColor(hex: "#FFD24C"))
        case .hole:        return makeHole()
        }
    }

    private static func fallbackBox(fringe: UIColor) -> SKNode {
        let node = SKShapeNode(rectOf: CGSize(width: 40, height: 40), cornerRadius: 6)
        node.fillColor = fringe
        node.strokeColor = .white
        node.lineWidth = 2
        return node
    }

    private static func makeRing(color: UIColor) -> SKNode {
        let root = SKNode()
        let ring = SKShapeNode(circleOfRadius: 40)
        ring.fillColor = .clear
        ring.strokeColor = color
        ring.lineWidth = 9
        ring.glowWidth = 4
        root.addChild(ring)
        let inner = SKShapeNode(circleOfRadius: 30)
        inner.fillColor = color.withAlphaComponent(0.12)
        inner.strokeColor = .clear
        root.addChild(inner)
        root.run(.repeatForever(.sequence([
            .scale(to: 1.1, duration: 0.5),
            .scale(to: 0.92, duration: 0.5),
        ])))
        return root
    }

    private static func makeHole() -> SKNode {
        let node = SKShapeNode(ellipseOf: CGSize(width: 120, height: 46))
        node.fillColor = UIColor.black.withAlphaComponent(0.92)
        node.strokeColor = UIColor(hex: "#2A1E4A")
        node.lineWidth = 3
        node.name = "hole"
        return node
    }

    // MARK: - Projectiles

    static func makeBullet(level: Int) -> SKNode {
        let name = level >= 3 ? "rocket" : "laser"
        let width: CGFloat = level >= 3 ? 34 : 22
        if let node = sprite(name, width: width, fallback: proceduralBullet(level: level)) as? SKSpriteNode {
            return node
        }
        return proceduralBullet(level: level)
    }

    private static func proceduralBullet(level: Int) -> SKNode {
        let node = SKShapeNode(rectOf: CGSize(width: 24, height: 8), cornerRadius: 4)
        node.fillColor = level >= 3 ? UIColor(hex: "#FF7A3D") : UIColor(hex: "#FFE24C")
        node.strokeColor = .white
        node.lineWidth = 2
        return node
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
