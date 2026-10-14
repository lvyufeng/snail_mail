import SpriteKit
import UIKit

/// Pseudo-3D highway racer. The road is projected from a list of segments
/// (curved, with hills) and everything on it — parcels, salt, asteroids,
/// slugs, turrets, rings and the post office — is billboarded on top, exactly
/// how the original mixed a 3D world with 2D animated sprites.
final class GameScene: SKScene {

    // MARK: - Tunables

    private let cameraHeight: CGFloat = 1000
    private let cameraDepth: CGFloat = 1.0 / tan((100.0 / 2.0) * .pi / 180.0) // ≈ 0.84
    private let roadWidth = TrackBuilder.roadWidth
    private let segmentLength = TrackBuilder.segmentLength
    private let drawDistance = 220
    private let playerZ: CGFloat
    private let wallRatio: CGFloat = 0.45

    // MARK: - Data

    private let mode: GameMode
    private let level: Int
    private let config: LevelConfig
    /// Debug/screenshot hook: skip the "tap to start" screen and race at once.
    var autoStart = false
#if DEBUG
    /// Set by the `-weapon N` screenshot hook so projectiles appear without a held touch.
    var debugAutoFire = false
#endif
    private var segments: [RoadSegment] = []
    private var trackLength: CGFloat = 1
    private var fringe: UIColor

    private(set) var state = RaceState()
    var onStateChange: ((RaceState) -> Void)?
    var onFinish: ((Bool) -> Void)?

    // MARK: - Player

    private var positionZ: CGFloat = 0        // camera z along the track
    private var playerX: CGFloat = 0         // -1...1 across the road
    private var targetX: CGFloat = 0
    private var currentSpeed: CGFloat = 0
    private var baseTargetSpeed: CGFloat = 1
    private var touching = false
    private var fireCooldown: CGFloat = 0
    private var boostUntil: CGFloat = 0
    private var invincibleUntil: CGFloat = 0
    private var elapsed: CGFloat = 0
    private var lastUpdate: TimeInterval = 0

    // MARK: - Nodes

    private let roadLayer = SKNode()
    private let entityLayer = SKNode()
    private let fxLayer = SKNode()
    private var snail = SKNode()
    private var starLayers: [SKNode] = []
    private var fogNode = SKNode()

    private var roadPool: [SKShapeNode] = []      // tan cells
    private var roadPoolB: [SKShapeNode] = []     // orange cells
    private var wallLeftPool: [SKShapeNode] = []
    private var wallRightPool: [SKShapeNode] = []
    private var entityPool: [EntityKind: [SKNode]] = [:]
    private var entityUse: [EntityKind: Int] = [:]
    /// Bullets are pooled per weapon tier so an upgrade immediately swaps the
    /// shared pool's look — a tier-1 pellet must never be reused as a rocket.
    private var bulletPool: [Int: [SKNode]] = [:]
    private var bulletUse: [Int: Int] = [:]

    // MARK: - Init

    init(mode: GameMode, level: Int, size: CGSize) {
        self.mode = mode
        self.level = level
        self.config = LevelConfig.forMode(mode, level: level)
        self.playerZ = cameraHeight * (1.0 / tan((100.0 / 2.0) * .pi / 180.0))
        self.fringe = UIColor(
            red: config.fringe.x / 255,
            green: config.fringe.y / 255,
            blue: config.fringe.z / 255,
            alpha: 1
        )
        super.init(size: size)
        self.scaleMode = .resizeFill
        self.backgroundColor = UIColor(hex: backgroundHex(for: config.background))
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

#if DEBUG
    /// Screenshot hooks: `-weapon N` starts at a weapon tier with autofire enabled.
    private func applyDebugArguments() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-weapon"), i + 1 < args.count,
              let level = Int(args[i + 1]) else { return }
        state.weaponLevel = max(1, min(level, state.maxWeaponLevel))
        state.suitStep = min(level - 1, Suit.allCases.count - 1)
        debugAutoFire = true
    }
#endif

    private func backgroundHex(for name: String) -> String {
        switch name {
        case "SpaceRed": "#2A0A22"
        case "SpaceGreen": "#06251F"
        case "SpaceBlue": "#0A1533"
        default: "#150A2C"
        }
    }

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        buildBackground()
        roadLayer.zPosition = 0
        addChild(roadLayer)
        entityLayer.zPosition = 5
        addChild(entityLayer)
        fxLayer.zPosition = 20
        addChild(fxLayer)
        preparePools()
        buildSnail()
        resetTrack()
        #if DEBUG
        applyDebugArguments()
        #endif
        if autoStart { startRace() }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-forcefinish") {
            startRace()
            finish(won: true)
        }
        #endif
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        buildBackground()
    }

    private func buildBackground() {
        guard size.width > 0, size.height > 0 else { return }
        childNode(withName: "sky")?.removeFromParent()
        let sky = SKNode()
        sky.name = "sky"
        sky.zPosition = -100

        let top = UIColor(hex: backgroundHex(for: config.background))
        let grad = Sprites.gradientTexture(size: CGSize(width: 8, height: size.height),
                                           colors: [top, UIColor(hex: "#140A2C"), UIColor(hex: "#06040D")])
        let backdrop = SKSpriteNode(texture: grad)
        backdrop.size = size
        backdrop.position = CGPoint(x: size.width / 2, y: size.height / 2)
        sky.addChild(backdrop)

        let g1 = SKSpriteNode(texture: Sprites.radialTexture(size: 512, color: UIColor(hex: "#7A1E7A")))
        g1.size = CGSize(width: size.width * 2.1, height: size.width * 2.1)
        g1.position = CGPoint(x: size.width * 0.15, y: size.height * 0.92)
        g1.alpha = 0.55
        sky.addChild(g1)
        let g2 = SKSpriteNode(texture: Sprites.radialTexture(size: 512, color: UIColor(hex: "#1B3B7A")))
        g2.size = CGSize(width: size.width * 1.9, height: size.width * 1.9)
        g2.position = CGPoint(x: size.width * 0.95, y: size.height * 0.72)
        g2.alpha = 0.5
        sky.addChild(g2)

        // Distant ringed planet.
        let planetR = size.width * 0.22
        let planet = SKShapeNode(circleOfRadius: planetR)
        planet.fillColor = UIColor(hex: "#6E3FA8")
        planet.strokeColor = UIColor(hex: "#B98CFF").withAlphaComponent(0.7)
        planet.lineWidth = 2
        planet.position = CGPoint(x: size.width * 0.8, y: size.height * 0.84)
        planet.glowWidth = 8
        sky.addChild(planet)
        let ring = SKShapeNode(ellipseOf: CGSize(width: planetR * 3.2, height: planetR * 0.8))
        ring.fillColor = .clear
        ring.strokeColor = UIColor(hex: "#58E1FF").withAlphaComponent(0.6)
        ring.lineWidth = 3
        ring.position = planet.position
        ring.zRotation = -0.32
        sky.addChild(ring)

        // Drifting stars.
        starLayers.removeAll()
        for _ in 0..<2 {
            let layer = SKNode()
            for _ in 0..<60 {
                let star = SKShapeNode(circleOfRadius: CGFloat.random(in: 0.8...2.4))
                star.fillColor = UIColor(white: 1, alpha: CGFloat.random(in: 0.3...0.95))
                star.strokeColor = .clear
                star.position = CGPoint(x: CGFloat.random(in: 0...size.width),
                                        y: CGFloat.random(in: size.height * 0.45...size.height))
                layer.addChild(star)
            }
            starLayers.append(layer)
            sky.addChild(layer)
        }

        addChild(sky)

        // Distance haze: a soft band centred on the horizon so the far road and
        // sprites dissolve into the sky instead of ending on a hard edge. It
        // sits above the track and billboards but below the snail, which stays
        // crisp in the near field.
        fogNode.removeFromParent()
        fogNode = SKNode()
        fogNode.zPosition = 8
        let fog = SKSpriteNode(texture: Sprites.gradientTexture(
            size: CGSize(width: 8, height: size.height * 0.5),
            colors: [UIColor(hex: "#160A30").withAlphaComponent(0),
                     UIColor(hex: "#1A1038").withAlphaComponent(0.96),
                     UIColor(hex: "#160A30").withAlphaComponent(0)],
            locations: [0, 0.5, 1]))
        fog.size = CGSize(width: size.width, height: size.height * 0.5)
        fog.position = CGPoint(x: size.width / 2, y: size.height * 0.5)
        fogNode.addChild(fog)
        addChild(fogNode)
    }

    private func preparePools() {
        for i in 0..<drawDistance {
            roadPool.append(makeQuadNode(fill: .black, z: -CGFloat(i)))
            roadPoolB.append(makeQuadNode(fill: .black, z: -CGFloat(i) + 0.05))
            wallLeftPool.append(makeQuadNode(fill: .black, z: -CGFloat(i) + 0.1))
            wallRightPool.append(makeQuadNode(fill: .black, z: -CGFloat(i) + 0.1))
            roadLayer.addChild(roadPool[i])
            roadLayer.addChild(roadPoolB[i])
            roadLayer.addChild(wallLeftPool[i])
            roadLayer.addChild(wallRightPool[i])
        }
    }

    private func makeQuadNode(fill: UIColor, z: CGFloat) -> SKShapeNode {
        let node = SKShapeNode()
        node.fillColor = fill
        node.strokeColor = .clear
        node.lineWidth = 0
        node.zPosition = z
        node.isHidden = true
        return node
    }

    private func buildSnail() {
        snail = Sprites.makeSnail()
        snail.zPosition = 30
        snail.setScale(1.15)
        addChild(snail)

        // Soft shadow under the snail so it sits on the road.
        let shadow = SKShapeNode(ellipseOf: CGSize(width: 120, height: 26))
        shadow.fillColor = UIColor.black.withAlphaComponent(0.28)
        shadow.strokeColor = .clear
        shadow.zPosition = 29
        shadow.name = "snailshadow"
        addChild(shadow)
    }

    private func resetTrack() {
        segments = TrackBuilder.build(config)
        trackLength = CGFloat(segments.count) * segmentLength

        state = RaceState()
        state.maxSpeed = Double(baseSpeed(for: config.speed))
        state.trackLength = Double(trackLength)
        state.quota = config.quota
        state.maxMeter = 100
        state.postalMeter = 100
        state.weaponLevel = 1
        baseTargetSpeed = baseSpeed(for: config.speed)
        currentSpeed = baseTargetSpeed * 0.4
        positionZ = 0
        playerX = 0
        targetX = 0
        elapsed = 0
        boostUntil = 0
        invincibleUntil = 0
        state.phase = .ready
        publish()
    }

    private func baseSpeed(for level: CGFloat) -> CGFloat {
        // Original "Speed" runs 0...100; map to roughly 3000...14000 units/s.
        3000 + (level / 100) * 11000
    }

    // MARK: - Control

    func startRace() {
        state.phase = .running
        state.elapsed = 0
        elapsed = 0
        publish()
    }

    func togglePause() {
        switch state.phase {
        case .running: state.phase = .paused
        case .paused: state.phase = .running
        default: break
        }
        publish()
    }

    func steer(toFraction x: CGFloat) { targetX = x }

    func setTouching(_ touching: Bool) { self.touching = touching }

    // MARK: - Update

    override func update(_ currentTime: TimeInterval) {
        defer { lastUpdate = currentTime }
        guard lastUpdate > 0 else { return }
        let dt = min(currentTime - lastUpdate, 1.0 / 30.0)
        let fdt = CGFloat(dt)

        scrollStars(fdt: fdt)
        guard state.phase == .running else { renderRoad(); return }

        elapsed += fdt
        state.elapsed = Double(elapsed)

        updateSpeed(fdt: fdt)
        updateSteering(fdt: fdt)

        let move = currentSpeed * fdt
        positionZ += move
        state.distance = Double(positionZ)
        state.speed = Double(currentSpeed)

        if positionZ >= trackLength {
            positionZ = trackLength
            finish(won: state.quotaMet)
            renderRoad()
            return
        }

        if touching || debugAutoFire {
            fireCooldown -= fdt
            if fireCooldown <= 0 {
                fireCooldown = state.weaponLevel >= 3 ? 0.16 : 0.26
                fire()
            }
        }
        updateBullets(fdt: fdt)
        handleCollisions()
        updateInvincibility()
        renderRoad()
        publish()
    }

    private func updateSpeed(fdt: CGFloat) {
        var target = baseTargetSpeed
        if elapsed < boostUntil { target = baseTargetSpeed * 1.4 }
        currentSpeed += (target - currentSpeed) * min(1, fdt * 0.7)
    }

    private func updateSteering(fdt: CGFloat) {
        playerX += (targetX - playerX) * min(1, fdt * 6)
        playerX = max(-1, min(1, playerX))
    }

    private func scrollStars(fdt: CGFloat) {
        let speed = currentSpeed / max(baseTargetSpeed, 1)
        for (i, layer) in starLayers.enumerated() {
            let s = (i == 0 ? 20.0 : 60.0) * speed
            for star in layer.children {
                star.position.y -= CGFloat(s) * fdt
                if star.position.y < size.height * 0.4 {
                    star.position.y = size.height + 4
                    star.position.x = CGFloat.random(in: 0...size.width)
                }
            }
        }
    }

    // MARK: - Shooting & collisions

    private func fire() {
        let bullet = obtainBullet()
        let start = CGPoint(x: snail.position.x + 30, y: snail.position.y + 6)
        bullet.position = start
        bullet.isHidden = false
        bullet.setScale(1)
        bullet.zRotation = .pi / 2   // nose points up the road
        bullet.removeAllActions()
        bullet.run(.sequence([
            .move(to: CGPoint(x: size.width * 0.5 + playerX * 60, y: size.height * 0.55), duration: 0.16),
            .fadeOut(withDuration: 0.05),
            .hide(),
            .fadeIn(withDuration: 0),
        ]))
        Sound.shared.play(.shoot)
        hitScan()
    }

    private func hitScan() {
        let playerSegIndex = segmentIndex(at: positionZ + playerZ)
        let range = 2...48
        // Rockets have a wider warhead, so they reach a little further across the
        // road than the early pellets.
        let reach: CGFloat = state.weaponLevel >= 3 ? 0.30 : 0.22
        for d in range {
            let seg = segments[(playerSegIndex + d) % segments.count]
            for spec in seg.sprites where spec.kind.isShootable {
                if abs(spec.offset - playerX) < reach {
                    destroy(spec, in: seg)
                    return
                }
            }
        }
    }

    private func destroy(_ spec: EntitySpec, in seg: RoadSegment) {
        seg.sprites.removeAll { $0.kind == spec.kind && $0.offset == spec.offset }
        state.score += 25
        spawnBurst(atSegment: seg.index)
    }

    private func handleCollisions() {
        let playerSegIndex = segmentIndex(at: positionZ + playerZ)
        let window = [playerSegIndex - 1, playerSegIndex, playerSegIndex + 1, playerSegIndex + 2]
        var toRemove: [(RoadSegment, EntitySpec)] = []
        for idx in window {
            let seg = segments[((idx % segments.count) + segments.count) % segments.count]
            for spec in seg.sprites {
                guard abs(spec.offset - playerX) < 0.16 else { continue }
                switch spec.kind {
                case .parcel:
                    state.parcels += 1
                    state.score += 10
                    Sound.shared.play(.collect)
                    toRemove.append((seg, spec))
                case .heart:
                    state.postalMeter = min(state.maxMeter, state.postalMeter + 25)
                    state.score += 5
                    Sound.shared.play(.collect)
                    toRemove.append((seg, spec))
                case .ringUpgrade:
                    state.weaponLevel = min(state.maxWeaponLevel, state.weaponLevel + 1)
                    Sound.shared.play(.upgrade)
                    toRemove.append((seg, spec))
                case .ringExplode:
                    state.score += 40
                    toRemove.append((seg, spec))
                case .ringSlow:
                    currentSpeed *= 0.6
                    toRemove.append((seg, spec))
                case .suitSpade, .suitClub, .suitHeart, .suitDiamond:
                    guard let suit = spec.kind.suit else { break }
                    if suit.rawValue == state.suitStep {
                        // Correct next rung: climb the ladder.
                        state.suitStep += 1
                        state.score += 30
                        state.postalMeter = min(state.maxMeter, state.postalMeter + 6)
                        Sound.shared.play(.upgrade)
                        if state.suitStep >= Suit.allCases.count {
                            // Full ♠♣♥♦ climb pays out the top weapon tier.
                            state.weaponLevel = state.maxWeaponLevel
                            state.score += 150
                        }
                        toRemove.append((seg, spec))
                    } else if suit.rawValue > state.suitStep {
                        // Skipped a rung: the gate zaps you and stays put.
                        damage(6, seg: seg)
                    }
                    // A suit already climbed is inert scenery.
                case .salt:
                    damage(10, seg: seg)
                    toRemove.append((seg, spec))
                case .asteroid:
                    currentSpeed *= 0.5
                    damage(4, seg: seg)
                    toRemove.append((seg, spec))
                case .slug:
                    damage(12, seg: seg)
                    toRemove.append((seg, spec))
                case .turret:
                    damage(14, seg: seg)
                case .hole:
                    damage(16, seg: seg)
                case .postOffice:
                    break
                }
            }
        }
        for (seg, spec) in toRemove {
            seg.sprites.removeAll { $0.kind == spec.kind && $0.offset == spec.offset }
            spawnBurst(atSegment: seg.index)
        }
    }

    private func damage(_ amount: Double, seg: RoadSegment) {
        guard config.damageEnabled else { return }
        // Brief invulnerability after any hit. Fixed obstacles (holes, turrets)
        // stay on the road, so without this the snail would keep taking damage
        // every frame it overlapped one and die in an instant.
        guard elapsed >= invincibleUntil else { return }
        invincibleUntil = elapsed + 0.75
        state.postalMeter = max(0, state.postalMeter - amount)
        Sound.shared.play(.hit)
        if state.postalMeter <= 0 {
            finish(won: false)
        }
    }

    private func updateInvincibility() {
        state.invincible = elapsed < invincibleUntil
    }

    // MARK: - Bullets

    private func obtainBullet() -> SKNode {
        let level = state.weaponLevel
        var arr = bulletPool[level] ?? []
        let index = bulletUse[level] ?? 0
        if index < arr.count {
            bulletUse[level] = index + 1
            return arr[index]
        }
        let node = Sprites.makeBullet(level: level)
        node.zPosition = 25
        fxLayer.addChild(node)
        arr.append(node)
        bulletPool[level] = arr
        bulletUse[level] = index + 1
        return node
    }

    private func updateBullets(fdt: CGFloat) {
        bulletUse.removeAll()
    }

    private func spawnBurst(atSegment index: Int) {
        let burst = SKShapeNode(circleOfRadius: 20)
        burst.fillColor = UIColor(hex: "#FFD24C").withAlphaComponent(0.7)
        burst.strokeColor = .white
        burst.lineWidth = 3
        burst.position = CGPoint(x: size.width * 0.5, y: size.height * 0.22)
        burst.zPosition = 26
        fxLayer.addChild(burst)
        burst.run(.sequence([
            .group([.scale(to: 2.4, duration: 0.22), .fadeOut(withDuration: 0.22)]),
            .removeFromParent(),
        ]))
    }

    // MARK: - Rendering

    /// The projection math is done in canvas space (y grows downward, like the
    /// classic pseudo-3D racer). SpriteKit's y axis points up, so flip when we
    /// actually place geometry.
    private func fy(_ y: CGFloat) -> CGFloat { size.height - y }

    private func renderRoad() {
        for i in 0..<drawDistance {
            roadPool[i].isHidden = true
            roadPoolB[i].isHidden = true
            wallLeftPool[i].isHidden = true
            wallRightPool[i].isHidden = true
        }
        for value in entityUse.keys { entityUse[value] = 0 }

        let baseSegment = segments[segmentIndex(at: positionZ)]
        let basePercent = percentRemaining(positionZ, segmentLength)
        let playerSeg = segments[segmentIndex(at: positionZ + playerZ)]
        let playerPercent = percentRemaining(positionZ + playerZ, segmentLength)
        let playerY = interpolate(playerSeg.p1.world.y, playerSeg.p2.world.y, playerPercent)

        var maxy = size.height
        var x: CGFloat = 0
        var dx: CGFloat = -(baseSegment.curve * basePercent)

        for n in 0..<drawDistance {
            let seg = segments[(baseSegment.index + n) % segments.count]
            seg.looped = seg.index < baseSegment.index
            seg.clip = maxy

            let camZAdjust = seg.looped ? trackLength : 0
            let camX = playerX * roadWidth - x
            let camX2 = playerX * roadWidth - x - dx
            let camY = playerY + cameraHeight
            let camZ = positionZ - camZAdjust

            project(&seg.p1, cameraX: camX, cameraY: camY, cameraZ: camZ)
            project(&seg.p2, cameraX: camX2, cameraY: camY, cameraZ: camZ)

            x += dx
            dx += seg.curve

            if seg.p1.camera.z <= cameraDepth || seg.p2.screenY >= seg.p1.screenY || seg.p2.screenY >= maxy {
                continue
            }

            drawSegment(seg, n: n)
            maxy = seg.p2.screenY
        }

        renderEntities(baseSegment: baseSegment)

        // Player.
        snail.position = CGPoint(x: size.width * 0.5, y: size.height * 0.17)
        snail.zRotation = -playerX * 0.22
        Sprites.setBoost(snail, on: elapsed < boostUntil || currentSpeed > baseTargetSpeed * 1.05)
        // Blink while the post-hit invulnerability is active.
        snail.alpha = elapsed < invincibleUntil ? 0.45 + 0.55 * abs(sin(elapsed * 22)) : 1
        let bob = sin(elapsed * 14) * 2
        snail.position.y += bob
        if let shadow = childNode(withName: "snailshadow") {
            shadow.position = CGPoint(x: snail.position.x, y: snail.position.y - 34)
            shadow.zRotation = snail.zRotation
        }
    }

    private func drawSegment(_ seg: RoadSegment, n: Int) {
        // The original road is a diamond lattice of sandy-tan and burnt-orange
        // tiles (see objects_world00_track0). Reproduce it as a checkerboard of
        // column cells whose parity alternates with depth as well as across the
        // road, so the pattern scrolls toward the camera.
        let l1 = seg.p1.screenX - seg.p1.screenW, r1 = seg.p1.screenX + seg.p1.screenW
        let l2 = seg.p2.screenX - seg.p2.screenW, r2 = seg.p2.screenX + seg.p2.screenW
        let y1 = fy(seg.p1.screenY), y2 = fy(seg.p2.screenY)
        let tall = abs(y1 - y2) >= 3

        let evenPath = CGMutablePath()
        let oddPath = CGMutablePath()
        if tall {
            for c in 0..<checkCols {
                let f0 = CGFloat(c) / CGFloat(checkCols)
                let f1 = CGFloat(c + 1) / CGFloat(checkCols)
                let ax0 = l1 + (r1 - l1) * f0, ax1 = l1 + (r1 - l1) * f1
                let bx0 = l2 + (r2 - l2) * f0, bx1 = l2 + (r2 - l2) * f1
                let target = ((c + seg.index) % 2 == 0) ? evenPath : oddPath
                target.move(to: CGPoint(x: ax0, y: y1))
                target.addLine(to: CGPoint(x: ax1, y: y1))
                target.addLine(to: CGPoint(x: bx1, y: y2))
                target.addLine(to: CGPoint(x: bx0, y: y2))
                target.closeSubpath()
            }
        } else {
            evenPath.move(to: CGPoint(x: l1, y: y1))
            evenPath.addLine(to: CGPoint(x: r1, y: y1))
            evenPath.addLine(to: CGPoint(x: r2, y: y2))
            evenPath.addLine(to: CGPoint(x: l2, y: y2))
            evenPath.closeSubpath()
        }
        roadPool[n].isHidden = false
        roadPool[n].fillColor = GameScene.roadTan
        roadPool[n].path = evenPath
        roadPoolB[n].isHidden = oddPath.isEmpty
        roadPoolB[n].fillColor = GameScene.roadOrange
        roadPoolB[n].path = oddPath

        // Fringe walls on both sides, tinted with the level's fringe colour.
        let lh1 = seg.p1.screenW * wallRatio
        let lh2 = seg.p2.screenW * wallRatio
        let lx1 = seg.p1.screenX - seg.p1.screenW
        let lx2 = seg.p2.screenX - seg.p2.screenW
        let rx1 = seg.p1.screenX + seg.p1.screenW
        let rx2 = seg.p2.screenX + seg.p2.screenW

        wallLeftPool[n].isHidden = false
        wallLeftPool[n].fillColor = fringe
        wallLeftPool[n].path = quad(lx1, fy(seg.p1.screenY), lx1, fy(seg.p1.screenY - lh1),
                                    lx2, fy(seg.p2.screenY - lh2), lx2, fy(seg.p2.screenY))
        wallRightPool[n].isHidden = false
        wallRightPool[n].fillColor = fringe
        wallRightPool[n].path = quad(rx1, fy(seg.p1.screenY), rx1, fy(seg.p1.screenY - lh1),
                                     rx2, fy(seg.p2.screenY - lh2), rx2, fy(seg.p2.screenY))
    }

    private static let roadTan = UIColor(hex: "#C18E4C")
    private static let roadOrange = UIColor(hex: "#C35612")
    private let checkCols = 6

    private func renderEntities(baseSegment: RoadSegment) {
        let baseIndex = baseSegment.index
        for n in 1..<drawDistance {
            let seg = segments[(baseIndex + n) % segments.count]
            guard !seg.sprites.isEmpty else { continue }
            let p = seg.p1
            guard p.scale > 0, !p.screenW.isNaN else { continue }
            for spec in seg.sprites {
                let node = obtainEntity(spec.kind)
                let ex = p.screenX + spec.offset * p.screenW
                let ey = fy(p.screenY)
                node.position = CGPoint(x: ex, y: ey)
                let spriteWidth = p.screenW * (spec.kind == .postOffice ? 1.1 : 0.42)
                let scale = spriteWidth / Sprites.entityBaseWidth(spec.kind)
                node.setScale(max(0.02, scale))
                node.isHidden = false
                node.zPosition = -CGFloat(n) + 0.5
                if spec.kind == .hole {
                    node.position = CGPoint(x: p.screenX, y: ey)
                    node.setScale(max(0.05, p.screenW * 0.9 / 120))
                }
            }
        }
        // Hide unused pooled entities.
        for (kind, nodes) in entityPool {
            let used = entityUse[kind] ?? 0
            if used < nodes.count {
                for i in used..<nodes.count { nodes[i].isHidden = true }
            }
        }
    }

    private func obtainEntity(_ kind: EntityKind) -> SKNode {
        var arr = entityPool[kind] ?? []
        let idx = entityUse[kind] ?? 0
        if idx < arr.count {
            entityUse[kind] = idx + 1
            return arr[idx]
        }
        let node = Sprites.makeEntity(kind, fringe: fringe)
        node.zPosition = 6
        entityLayer.addChild(node)
        arr.append(node)
        entityPool[kind] = arr
        entityUse[kind] = idx + 1
        return node
    }

    // MARK: - Projection helpers

    private func project(_ p: inout Projection, cameraX: CGFloat, cameraY: CGFloat, cameraZ: CGFloat) {
        p.camera.x = p.world.x - cameraX
        p.camera.y = p.world.y - cameraY
        p.camera.z = p.world.z - cameraZ
        let z = max(p.camera.z, 0.0001)
        p.scale = cameraDepth / z
        p.screenX = size.width / 2 + p.scale * p.camera.x * size.width / 2
        p.screenY = size.height / 2 - p.scale * p.camera.y * size.height / 2
        p.screenW = p.scale * roadWidth * size.width / 2
    }

    private func quad(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat,
                      _ x3: CGFloat, _ y3: CGFloat, _ x4: CGFloat, _ y4: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x1, y: y1))
        path.addLine(to: CGPoint(x: x2, y: y2))
        path.addLine(to: CGPoint(x: x3, y: y3))
        path.addLine(to: CGPoint(x: x4, y: y4))
        path.closeSubpath()
        return path
    }

    private func segmentIndex(at z: CGFloat) -> Int {
        guard !segments.isEmpty else { return 0 }
        var idx = Int(floor(z / segmentLength))
        idx = ((idx % segments.count) + segments.count) % segments.count
        return idx
    }

    private func percentRemaining(_ z: CGFloat, _ total: CGFloat) -> CGFloat {
        guard total > 0 else { return 0 }
        return (z.truncatingRemainder(dividingBy: total)) / total
    }

    private func interpolate(_ a: CGFloat, _ b: CGFloat, _ p: CGFloat) -> CGFloat {
        a + (b - a) * p
    }

    // MARK: - Finish

    private func finish(won: Bool) {
        guard state.phase == .running else { return }
        state.phase = .finished(won: won)
        if won { state.score += 500 + state.parcels * 5 }
        Sound.shared.play(won ? .win : .lose)
        publish()
        onFinish?(won)
    }

    private func publish() { onStateChange?(state) }
}
