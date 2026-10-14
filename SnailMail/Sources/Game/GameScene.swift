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
    /// How wide the pit is, as a fraction of the half-road: the pit is drawn
    /// 0.9 × screenW across and the snail drops in over the same span.
    private let holeHalfWidth: CGFloat = 0.45
    private let snailBaseScale: CGFloat = 1.15
    /// Seconds the snail spends tumbling down a hole before climbing out.
    private let fallDuration: CGFloat = 0.9
    /// Seconds the snail spends airborne after hitting a ramp or trampoline.
    private let hopDuration: CGFloat = 0.7
    /// Where the muzzle sits, measured up the road from the camera. The snail
    /// is drawn at a fixed screen height, so this is the distance whose
    /// projection lands on the gun.
    private let muzzleAhead: CGFloat = 380
    /// How far a shot carries before it burns out.
    private let bulletRange: CGFloat = 9000

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
    /// >= 0 while the snail is dropping into a hole; -1 the rest of the time.
    private var fallTimer: CGFloat = -1
    /// Where the pit sat across the road, so the snail climbs out beside it.
    private var fallOffset: CGFloat = 0
    /// >= 0 while the snail is flying off a ramp; -1 the rest of the time.
    private var hopTimer: CGFloat = -1
    private var hopPower: CGFloat = 0
    /// Left while the jetpack carries the snail over everything on the road.
    private var jetpackUntil: CGFloat = 0

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
    /// Idle bullets are pooled per weapon tier so an upgrade immediately swaps
    /// the look — a tier-1 pellet must never come back as a rocket.
    private var bulletPool: [Int: [SKNode]] = [:]
    private var bullets: [Bullet] = []

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
            // Faithful to a real finish: the player has driven to the end of the
            // route, which is the state REPLAY has to recover from.
            positionZ = trackLength
            state.distance = Double(positionZ)
            state.parcels = state.quota
            state.sheet.parcelCollect = state.quota * 100
            state.sheet.ring = 600
            state.sheet.slug = 1200
            state.sheet.garbage = 800
            finish(won: true)
        }
        if ProcessInfo.processInfo.arguments.contains("-pittest") {
            startRace()
            // Drop a pit directly under the snail so the fall can be watched.
            let idx = segmentIndex(at: positionZ + playerZ)
            segments[idx].sprites.removeAll { $0.kind == .hole }
            segments[idx].sprites.append(EntitySpec(kind: .hole, offset: 0, depth: 0.5))
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
        snail.setScale(snailBaseScale)
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
        segments = TrackBuilder.build(config, mode: mode, level: level)
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
        fallTimer = -1
        fallOffset = 0
        hopTimer = -1
        hopPower = 0
        jetpackUntil = 0
        fireCooldown = 0
        clearBullets()
        snail.setScale(snailBaseScale)
        snail.zRotation = 0
        snail.alpha = 1
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

    /// Replay: a brand new run, not a resumed one. Without the track reset the
    /// camera would still be parked on the finish line, so the race would
    /// re-finish on the very next frame and the results screen would look like
    /// it swallowed the tap.
    func restartRace() {
        resetTrack()
        startRace()
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

        // Mid-fall the snail has no control and no forward drive: it plunges,
        // then climbs back out behind the pit.
        if fallTimer >= 0 {
            updateFall(fdt: fdt)
            renderRoad()
            publish()
            return
        }

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
        if hopTimer >= 0 {
            hopTimer += fdt
            if hopTimer >= hopDuration { hopTimer = -1 }
        }
        handleCollisions()
        updateInvincibility()
        renderRoad()
        // Shots are moved and resolved against this frame's projections.
        updateBullets(fdt: fdt)
        publish()
    }

    private func updateSpeed(fdt: CGFloat) {
        var target = baseTargetSpeed
        if elapsed < jetpackUntil { target = baseTargetSpeed * 1.5 }
        else if elapsed < boostUntil { target = baseTargetSpeed * 1.4 }
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

    /// A shot in flight. It carries a place on the road — distance along the
    /// track plus a lateral offset — instead of a screen position, so it
    /// converges on the vanishing point and shrinks with distance exactly like
    /// the world sprites. That is what makes it read as flying *down the road*
    /// rather than climbing at the sky.
    private struct Bullet {
        let node: SKNode
        let level: Int
        var z: CGFloat
        var offset: CGFloat
        var travel: CGFloat
        var lastPoint: CGPoint
    }

    private func fire() {
        let node = obtainBullet()
        node.isHidden = false
        node.alpha = 1
        node.setScale(1)
        node.zRotation = .pi / 2   // nose points up the road
        node.removeAllActions()
        bullets.append(Bullet(node: node,
                              level: state.weaponLevel,
                              z: positionZ + playerZ + muzzleAhead,
                              offset: playerX,
                              travel: 0,
                              lastPoint: .zero))
        Sound.shared.play(.shoot)
    }

    /// Runs every shot forward, re-projects it on the road and resolves the
    /// first thing it meets. Called after `renderRoad()`, so the segment
    /// projections it reads belong to this frame.
    private func updateBullets(fdt: CGFloat) {
        guard !bullets.isEmpty else { return }
        // A shot outruns the snail by a wide margin, so the target closes in
        // on its own while the tracer is still travelling.
        let step = max(currentSpeed, baseTargetSpeed) * 2.6 * fdt
        for i in bullets.indices.reversed() {
            var bullet = bullets[i]
            let from = bullet.z
            bullet.z += step
            bullet.travel += step

            if let (seg, spec, hitZ) = firstTarget(from: from, to: bullet.z,
                                                   offset: bullet.offset) {
                // Stop the tracer on the target, then pop it.
                bullet.z = hitZ
                place(&bullet)
                bullets[i] = bullet
                destroy(spec, in: seg)
                spawnBurst(at: bullet.node.position)
                retireBullet(at: i)
                continue
            }

            if bullet.travel > bulletRange {
                retireBullet(at: i)
                continue
            }
            place(&bullet)
            bullets[i] = bullet
        }
    }

    /// The first shootable thing between two points along the track. The whole
    /// span is swept, so a shot can never tunnel through a target at speed.
    private func firstTarget(from z0: CGFloat, to z1: CGFloat,
                             offset: CGFloat) -> (RoadSegment, EntitySpec, CGFloat)? {
        guard !segments.isEmpty else { return nil }
        // Rockets carry a wider warhead than the early pellets.
        let reach: CGFloat = state.weaponLevel >= 3 ? 0.30 : 0.22
        let first = segmentIndex(at: z0)
        let last = segmentIndex(at: z1)
        var idx = first
        var segStart = z0 - percentRemaining(z0, segmentLength) * segmentLength
        while true {
            let seg = segments[idx]
            for spec in seg.sprites where spec.kind.isShootable {
                if abs(spec.offset - offset) < reach {
                    return (seg, spec, segStart)
                }
            }
            if idx == last { break }
            idx = (idx + 1) % segments.count
            segStart += segmentLength
        }
        return nil
    }

    /// Moves a shot's node to its place on the road this frame.
    private func place(_ bullet: inout Bullet) {
        guard let p = roadPoint(z: bullet.z, offset: bullet.offset) else {
            bullet.node.isHidden = true
            return
        }
        bullet.node.isHidden = false
        bullet.node.position = p.point
        // 1.0 at the muzzle, tapering with distance the same way the sprites do.
        let muzzleHalfWidth = size.width * 0.5
        let taper = muzzleHalfWidth > 0 ? p.halfWidth / muzzleHalfWidth : 0
        bullet.node.setScale(min(1.6, max(0.12, taper * 1.5)))
        // Burn out rather than blink off at the horizon.
        let fade = (bullet.travel / bulletRange - 0.6) / 0.4
        bullet.node.alpha = 1 - 0.85 * max(0, min(1, fade))
        if bullet.lastPoint != .zero {
            let dx = p.point.x - bullet.lastPoint.x
            let dy = p.point.y - bullet.lastPoint.y
            if abs(dx) + abs(dy) > 0.5 {
                bullet.node.zRotation = atan2(dy, dx)
            }
        }
        bullet.lastPoint = p.point
    }

    /// Projects a point sitting on the road surface `z` units along the track,
    /// `offset` across it (−1...1), using the perspective the sprites use.
    private func roadPoint(z: CGFloat, offset: CGFloat) -> (point: CGPoint, halfWidth: CGFloat)? {
        guard !segments.isEmpty, segmentLength > 0 else { return nil }
        let base = segmentIndex(at: positionZ)
        let f = (z - CGFloat(base) * segmentLength) / segmentLength
        guard f >= 0, f < CGFloat(drawDistance - 1) else { return nil }
        let d = Int(f)
        let pct = f - CGFloat(d)
        let seg = segments[(base + d) % segments.count]
        let sx = interpolate(seg.p1.screenX, seg.p2.screenX, pct)
        let sy = interpolate(seg.p1.screenY, seg.p2.screenY, pct)
        let sw = interpolate(seg.p1.screenW, seg.p2.screenW, pct)
        return (CGPoint(x: sx + offset * sw, y: fy(sy)), sw)
    }

    private func destroy(_ spec: EntitySpec, in seg: RoadSegment) {
        seg.sprites.removeAll { $0.kind == spec.kind && $0.offset == spec.offset }
        switch spec.kind {
        case .slug: state.sheet.slug += 400
        default:    state.sheet.garbage += 200
        }
    }

    /// The blast of a yellow ring: every enemy in the stretch of road around
    /// the snail is destroyed and scores as garbage, matching the tutorial's
    /// "Yellow Rings blow up my enemies".
    @discardableResult
    private func detonateBlast() -> Int {
        guard !segments.isEmpty else { return 0 }
        let base = segmentIndex(at: positionZ + playerZ)
        var cleared = 0
        for d in 0...3 {
            let seg = segments[((base + d) % segments.count + segments.count) % segments.count]
            let victims = seg.sprites.filter { $0.kind == .enemy }
            guard !victims.isEmpty else { continue }
            for v in victims {
                seg.sprites.removeAll { $0.kind == .enemy && $0.offset == v.offset }
                cleared += 1
            }
        }
        if cleared > 0 {
            state.sheet.garbage += 200 * cleared
            spawnBurst(at: playerPoint())
        }
        return cleared
    }

    private func handleCollisions() {
        let playerSegIndex = segmentIndex(at: positionZ + playerZ)
        let window = [playerSegIndex - 1, playerSegIndex, playerSegIndex + 1, playerSegIndex + 2]
        var toRemove: [(RoadSegment, EntitySpec)] = []
        for idx in window {
            let seg = segments[((idx % segments.count) + segments.count) % segments.count]
            for spec in seg.sprites {
                // A pit is as wide as it looks; everything else is a point-sized
                // pick-up or hazard with a slim footprint.
                let tolerance = spec.kind == .hole
                    ? (spec.width > 0 ? spec.width : holeHalfWidth * 2) / 2 * 0.93
                    : 0.16
                guard abs(spec.offset - playerX) < tolerance else { continue }
                switch spec.kind {
                case .parcel:
                    state.parcels += 1
                    state.sheet.parcelCollect += 100
                    Sound.shared.play(.collect)
                    toRemove.append((seg, spec))
                case .heart:
                    state.postalMeter = min(state.maxMeter, state.postalMeter + 25)
                    state.sheet.bonus += 100
                    Sound.shared.play(.collect)
                    toRemove.append((seg, spec))
                case .ringUpgrade:
                    if state.weaponLevel < state.maxWeaponLevel {
                        // The power-up ring is the only way up the weapon ladder:
                        // blaster -> laser -> rocket launcher.
                        state.weaponLevel += 1
                        Sound.shared.play(.upgrade)
                    } else {
                        // Already at rockets. The original promises that once
                        // you have grabbed enough rings "I will become
                        // invincible", so a ring past the top of the ladder
                        // buys a spell of invulnerability and a bonus.
                        invincibleUntil = max(invincibleUntil, elapsed + 4)
                        state.sheet.bonus += 200
                        Sound.shared.play(.upgrade)
                    }
                    toRemove.append((seg, spec))
                case .ringExplode:
                    // The yellow ring reaches out and pops every enemy around
                    // it, exactly as the tutorial describes.
                    detonateBlast()
                    state.sheet.ring += 200
                    toRemove.append((seg, spec))
                case .ringSlow:
                    currentSpeed *= 0.6
                    toRemove.append((seg, spec))
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
                case .enemy:
                    guard elapsed >= invincibleUntil else {
                        // Invincible: plough straight through the pest.
                        state.sheet.garbage += 200
                        toRemove.append((seg, spec))
                        continue
                    }
                    // The highway pest shoves the snail toward the edge of the
                    // road as well as denting the meter.
                    damage(14, seg: seg)
                    targetX = max(-1, min(1, playerX + (playerX >= 0 ? 0.45 : -0.45)))
                    toRemove.append((seg, spec))
                case .barrier:
                    // A fence or cage pillar: cut the speed and nudge the snail
                    // off it, but leave the barrier standing.
                    currentSpeed *= 0.35
                    damage(8, seg: seg)
                    let push: CGFloat = playerX >= spec.offset ? 0.3 : -0.3
                    targetX = max(-1, min(1, playerX + push))
                case .turret:
                    damage(14, seg: seg)
                case .hole:
                    // A ramp launch or a jetpack carries the snail over a pit.
                    if hopTimer < 0 && elapsed >= jetpackUntil {
                        beginFall(offset: spec.offset)
                    }
                case .ramp:
                    launch(power: 1.0)
                case .trampoline:
                    launch(power: 1.5)
                case .jetpack:
                    jetpackUntil = elapsed + 3.5
                    invincibleUntil = max(invincibleUntil, jetpackUntil)
                    Sound.shared.play(.boost)
                    toRemove.append((seg, spec))
                case .ringNormal:
                    state.sheet.ring += 150
                    currentSpeed = min(baseTargetSpeed * 1.5,
                                       currentSpeed + baseTargetSpeed * 0.35)
                    Sound.shared.play(.collect)
                    toRemove.append((seg, spec))
                case .arch:
                    break
                case .postOffice:
                    break
                }
            }
        }
        for (seg, spec) in toRemove {
            seg.sprites.removeAll { $0.kind == spec.kind && $0.offset == spec.offset }
            spawnBurst(at: playerPoint())
        }
    }

    /// Where the snail itself sits on screen, for effects that fire on it.
    private func playerPoint() -> CGPoint {
        roadPoint(z: positionZ + playerZ, offset: playerX)?.point
            ?? CGPoint(x: size.width * 0.5, y: size.height * 0.2)
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

    // MARK: - Falling into a hole

    /// Fly off a ramp or trampoline: a short hop that clears pits and hazards,
    /// with a burst of speed for the landing.
    private func launch(power: CGFloat) {
        guard fallTimer < 0, hopTimer < 0 else { return }
        hopTimer = 0
        hopPower = power
        invincibleUntil = max(invincibleUntil, elapsed + hopDuration + 0.15)
        currentSpeed = min(baseTargetSpeed * 1.6,
                           currentSpeed + baseTargetSpeed * 0.5 * power)
        boostUntil = max(boostUntil, elapsed + 0.5)
        Sound.shared.play(.boost)
    }

    /// Drop the snail into a pit. Contact damage is suppressed while falling —
    /// the plunge itself is the punishment, and it is applied on the way out.
    private func beginFall(offset: CGFloat) {
        guard fallTimer < 0, state.phase == .running else { return }
        fallTimer = 0
        fallOffset = offset
        clearBullets()
        Sound.shared.play(.fall)
        spawnBurst(at: playerPoint())
    }

    private func updateFall(fdt: CGFloat) {
        fallTimer += fdt
        // Forward motion dies instantly — the snail is no longer on the road.
        currentSpeed = max(0, currentSpeed - fdt * 3000)
        state.speed = Double(currentSpeed)
        if fallTimer >= fallDuration { endFall() }
    }

    /// Climb back out: rewind a few segments, plant the snail on the side of the
    /// pit it did not fall through, and hand out a moment of mercy invincibility
    /// so it cannot immediately drop in again.
    private func endFall() {
        fallTimer = -1
        let side: CGFloat = fallOffset >= 0 ? -0.62 : 0.62
        positionZ = max(0, positionZ - segmentLength * 3)
        playerX = side
        targetX = side
        currentSpeed = baseTargetSpeed * 0.35
        state.speed = Double(currentSpeed)

        snail.setScale(snailBaseScale)
        snail.zRotation = 0
        snail.alpha = 1

        if config.damageEnabled {
            state.postalMeter = max(0, state.postalMeter - 16)
            Sound.shared.play(.hit)
            if state.postalMeter <= 0 {
                finish(won: false)
                return
            }
        }
        invincibleUntil = elapsed + 1.4
    }

    private func updateInvincibility() {
        state.invincible = elapsed < invincibleUntil
    }

    // MARK: - Bullets

    private func obtainBullet() -> SKNode {
        let level = state.weaponLevel
        var idle = bulletPool[level] ?? []
        if let node = idle.popLast() {
            bulletPool[level] = idle
            return node
        }
        let node = Sprites.makeBullet(level: level)
        node.zPosition = 25
        fxLayer.addChild(node)
        return node
    }

    private func retireBullet(at index: Int) {
        let bullet = bullets.remove(at: index)
        bullet.node.removeAllActions()
        bullet.node.isHidden = true
        bullet.node.alpha = 1
        bullet.node.setScale(1)
        bulletPool[bullet.level, default: []].append(bullet.node)
    }

    private func clearBullets() {
        for i in bullets.indices.reversed() { retireBullet(at: i) }
    }

    private func spawnBurst(at point: CGPoint) {
        let burst = SKShapeNode(circleOfRadius: 20)
        burst.fillColor = UIColor(hex: "#FFD24C").withAlphaComponent(0.7)
        burst.strokeColor = .white
        burst.lineWidth = 3
        burst.position = point
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
        if fallTimer >= 0 {
            // Tumbling down the pit: sink below the road, spin and shrink.
            let p = min(1, fallTimer / fallDuration)
            let ease = p * p
            snail.position = CGPoint(x: size.width * 0.5,
                                     y: size.height * 0.17 - 95 * ease)
            snail.zRotation = p * 5.6
            snail.setScale(snailBaseScale * (1 - 0.5 * ease))
            snail.alpha = 1 - 0.3 * p
        } else {
            snail.position = CGPoint(x: size.width * 0.5, y: size.height * 0.17)
            snail.zRotation = -playerX * 0.22
            snail.setScale(snailBaseScale)
            Sprites.setBoost(snail, on: elapsed < boostUntil || elapsed < jetpackUntil
                             || currentSpeed > baseTargetSpeed * 1.05)
            // Blink while the post-hit invulnerability is active.
            snail.alpha = elapsed < invincibleUntil ? 0.45 + 0.55 * abs(sin(elapsed * 22)) : 1
            snail.position.y += sin(elapsed * 14) * 2
            // Riding a ramp: arc the snail up and over the road.
            if hopTimer >= 0 {
                let p = hopTimer / hopDuration
                snail.position.y += sin(p * .pi) * 70 * hopPower
                snail.zRotation += sin(p * .pi) * 0.3 * hopPower
            }
        }
        if let shadow = childNode(withName: "snailshadow") {
            shadow.position = CGPoint(x: snail.position.x, y: snail.position.y - 34)
            shadow.zRotation = snail.zRotation
            shadow.alpha = fallTimer >= 0 ? max(0, 1 - fallTimer / fallDuration) : 1
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
                let widthFactor: CGFloat
                switch spec.kind {
                case .postOffice: widthFactor = 1.1
                case .hole:       widthFactor = spec.width > 0 ? spec.width : holeHalfWidth * 2
                default:          widthFactor = 0.42
                }
                let spriteWidth = p.screenW * widthFactor
                let scale = spriteWidth / Sprites.entityBaseWidth(spec.kind)
                node.setScale(max(0.02, scale))
                node.isHidden = false
                node.zPosition = -CGFloat(n) + 0.5
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
        // Hand the mail over: everything on board is delivered at the post
        // office, which is what the "Parcel Deliver" gauge measures.
        state.delivered = state.parcels
        if won {
            if state.quota > 0 { state.sheet.parcelDeliver += state.delivered * 500 }
            state.sheet.bonus += 1000
            // A full quota with the postal meter untouched is the original's
            // "PERFECT SCORE!".
            if state.quota > 0 && state.postalMeter >= state.maxMeter {
                state.sheet.bonus += 5000
            }
        }
        state.phase = .finished(won: won)
        Sound.shared.play(won ? .win : .lose)
        publish()
        onFinish?(won)
    }

    private func publish() { onStateChange?(state) }
}
