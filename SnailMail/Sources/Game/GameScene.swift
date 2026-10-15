import SpriteKit
import UIKit

/// Pseudo-3D highway racer. The road is projected from a list of segments
/// (curved, with hills) and everything on it — parcels, salt, asteroids,
/// slugs, turrets, rings and the post office — is billboarded on top, exactly
/// how the original mixed a 3D world with 2D animated sprites.
final class GameScene: SKScene {

    // MARK: - Tunables

    /// How high the camera rides over the highway. This, not the lens, is what
    /// sets how fast the road fans out down the frame: the highway on screen
    /// row `r` runs `roadWidth * (r - horizonRow) / cameraHeight` of a screen
    /// wide, half to each side of the centre. The retail courses are shot from a
    /// low, wide camera: their lanes widen at a steady screen-width per
    /// screen-height and are already most of the frame across by two thirds of
    /// the way down, which 1500 units above a 1500-unit highway reproduces.
    private let cameraHeight: CGFloat = 1500
    private let cameraDepth: CGFloat = 1.0 / tan((100.0 / 2.0) * .pi / 180.0) // ≈ 0.84
    /// The row the highway's vanishing point sits on, as a fraction of the
    /// screen height, counted from the top. A level camera would put it on the
    /// middle row, which leaves the near highway too short and everything that
    /// stands on it oversized. Rather than tilt the camera — which would shear
    /// every billboard and bend the lanes — the projection simply moves its
    /// centre up onto this row, the shift a rising-front lens makes.
    private let horizonRow: CGFloat = 0.30
    private let roadWidth = TrackBuilder.roadWidth
    private let segmentLength = TrackBuilder.segmentLength
    private let drawDistance = 220
    private let playerZ: CGFloat
    private let wallRatio: CGFloat = 0.45
    /// How wide the pit is, as a fraction of the half-road: the pit is drawn
    /// 0.9 × screenW across and the snail drops in over the same span.
    private let holeHalfWidth: CGFloat = 0.45
    /// How wide Turbo is drawn, as a fraction of the highway's full width at
    /// his own row on screen.
    ///
    /// The build's `turbo-base` mesh measures 0.606 of the nine units the road
    /// is across — `Sprites.snailModelWidth` — so a share of the road is the
    /// right way to size him; measuring him against the screen instead would
    /// stretch him on a tall portrait phone, where the near highway runs off
    /// both edges.
    ///
    /// Taken straight off that mesh, though, he covers 6.7% of the road and
    /// reads half again as wide as the build's own screenshots show him. Two
    /// things push him out. The baked frames hang his eye stalks and the gear
    /// bolted to his shell outside the mesh box, so sizing the mesh fills the
    /// share with his shell alone; and on the portrait frame the road at his
    /// row is wider than the screen, so the same share covers more of the
    /// view. The retail captures put the whole creature — shell, stalks and
    /// gear — at about a twentieth of the frame across (`ma_5` of the screen
    /// set, where he spans 32 of the 640 columns, and the road there already
    /// runs off both edges as it does here). Seven tenths of the mesh's share
    /// lands him on the same reading, and is what is drawn.
    private let snailRoadFraction: CGFloat =
        Sprites.snailModelWidth / roadModelWidth * 0.7
    /// Turbo's own width, in points, at the snapshot's screen scale.
    private var snailScale: CGFloat = 1
    /// Half the highway's on-screen width on Turbo's row, refreshed by
    /// `renderRoad()` from the segment he is racing over.
    private var snailRowHalfWidth: CGFloat = 0
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
    /// Seconds between the highway pests' return shots.
    private let enemyFireInterval: CGFloat = 1.3
    /// How far up the road, in segments, a pest will open fire. It is well
    /// beyond the snail's own range on purpose: a pest that waited until it was
    /// close enough to shoot would be dead before it ever got a shot off.
    private let enemyFireRange = 60
    /// The pests' bolt is a touch slower than the snail's own shots.
    private let enemyBulletSpeedFactor: CGFloat = 2.2

    // MARK: - Data

    private let mode: GameMode
    private let level: Int
    private let config: LevelConfig
    /// Debug/screenshot hook: skip the "tap to start" screen and race at once.
    var autoStart = false
    /// Set by the `-weapon N` screenshot hook so projectiles appear without a held touch.
    /// Always present so the fire loop compiles in release; only ever set under DEBUG.
    var debugAutoFire = false
    private var segments: [RoadSegment] = []
    private var trackLength: CGFloat = 1
    private var fringe: UIColor
    /// The roadside wall's fill — the retail fringe gradient tinted with
    /// `fringe`, or nil on a checkout without the retail art, where the walls
    /// stay flat.
    private var fringeWall: SKTexture?
    /// The two tones the road checkerboard alternates between, taken from the
    /// retail surface the level's `Track:` script selects.
    private var roadTan: UIColor
    private var roadOrange: UIColor

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
    /// The skid sound is played at most this often, so a twitchy drag does not
    /// turn into a wall of tyre noise.
    private var skidUntil: CGFloat = 0
    /// Counts down to the next puff of tyre smoke while a skid is running.
    private var skidClock: CGFloat = 0
    private var elapsed: CGFloat = 0
    /// This frame's slice of time, handed to Turbo's animation. Zero while the
    /// race is paused so he holds his pose.
    private var frameDelta: CGFloat = 0
    /// Until this time Turbo is playing the retail build's `damaged` clip, which
    /// is what he does after something bumps into him.
    private var hurtUntil: CGFloat = 0
    /// True once a slug has landed the killing blow: Turbo retreats into his
    /// shell and stays there for the results screen.
    private var slugged = false
    private var lastUpdate: TimeInterval = 0
    /// Screenshot hooks: a stream pinned by `-seed N`, so a scene lays its
    /// drifting stars out identically twice in a row, and `-freeze N`, which
    /// stops the clock after N frames so two captures of a running race show
    /// the same instant of the same course.
    private var sceneRandom = CourseRandom.launched()
    /// The seed the backdrop is laid out from. `didChangeSize` rebuilds it, so
    /// it opens a fresh stream from this rather than carrying on the scene's
    /// own, which would scatter the stars a little differently every time the
    /// view was resized.
    private let sceneSeed = CourseRandom.launchedSeed()
    private var framesToFreeze = -1
    private var framesRun = 0
    /// `-meterlock F`: debug only — the fraction of the postal tube the race is
    /// held at every frame.
    private var debugMeterLock: Double?
    /// `-turret N`: the tier of the pillar the debug hook keeps parked ahead.
    private var debugTurretTier: Int?
    private var debugTurretSegment: Int?
    /// >= 0 while the snail is dropping into a hole; -1 the rest of the time.
    private var fallTimer: CGFloat = -1
    /// `-ignoretnf`: debug only — pretend no row carries the `NoFall` tag, so a
    /// capture pair can show what the tag holds up.
    private var debugIgnoreNoFall = false
    /// Seconds into the fail-safe's `Time's Up` ramp, or -1 while no run has
    /// run out of time.
    private var timeUpAt: CGFloat = -1
    /// The build's fail-safe limit, in seconds of race clock: `0x43d1c8` fires
    /// when the shared run counter reaches 21 000 frames, and the build runs
    /// that counter once a frame at 60 Hz. `-timelimit N` shortens it for a
    /// screenshot.
    private var timeLimit: CGFloat {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-timelimit"), i + 1 < args.count,
           let seconds = Double(args[i + 1]) {
            return CGFloat(seconds)
        }
        return 350
    }
    /// How long `Time's Up` stays on the screen before the race ends: the
    /// ramp at `0xc(%esi)` climbs 0.00556 a frame, so the build holds the line
    /// for about three seconds and then tears it down (`0x445e00`).
    private let timeUpHold: CGFloat = 3
    /// Where the pit sat across the road, so the snail climbs out beside it.
    private var fallOffset: CGFloat = 0
    /// >= 0 while the snail is flying off a ramp; -1 the rest of the time.
    private var hopTimer: CGFloat = -1
    private var hopPower: CGFloat = 0
    /// Left while the jetpack carries the snail over everything on the road.
    private var jetpackUntil: CGFloat = 0
    /// How far the snail has got through `TrackData.tutorialScript`, or -1
    /// while it is still on the pieces before the first scripted line.
    private var tutorialStep = -1
    /// World z of the `JetPackOff` piece that ends the current jetpack flight,
    /// or 0 while it is a plain timed flight. The levels always drop the
    /// switch-off piece just past the gaps the jetpack is meant to clear, so
    /// the flight lasts as far as it has to and no further.
    private var jetpackOffZ: CGFloat = 0
    /// True while the jetpack is carrying the snail: it has not timed out and
    /// the snail has not yet reached the switch-off piece.
    private var jetpackActive: Bool {
        elapsed < jetpackUntil && (jetpackOffZ <= 0 || positionZ < jetpackOffZ)
    }
    /// True while the snail shrugs off hits: the brief post-hit grace, the
    /// jetpack carrying it over everything, or a weapon rung high enough to
    /// wear bit `0x80` of the ladder's capability mask — the top two rungs,
    /// which the build's hit routines at `0x444d0b` and `0x445093` step over
    /// entirely.
    private var invincible: Bool {
        jetpackActive || elapsed < invincibleUntil || state.weapon.invulnerable
    }
    /// Progress across the airborne void the snail is flying, 0...1, or -1
    /// while there is road under it. The jump pieces spell their gap as a run
    /// of blank rows, and the snail takes that as a ramp and arcs over.
    private var gapFlight: CGFloat = -1
    private var gapStartZ: CGFloat = 0
    private var gapLengthZ: CGFloat = 1
    /// How high, in points, the arc over the current gap reaches.
    private var gapArc: CGFloat = 0

    // MARK: - Nodes

    private let roadLayer = SKNode()
    private let entityLayer = SKNode()
    private let fxLayer = SKNode()
    private var snail = SKNode()
    private var starLayers: [SKNode] = []
    /// The retail backdrop: the level's own space art laid over the scene, how
    /// tall that copy is drawn, the rate its script asks it to drift at and how
    /// long the race has been running. `update` carries it, so the sky moves on
    /// the race's own clock.
    private var skyTiles: SKNode?
    private var skyTileHeight: CGFloat = 0
    private var skyDistort: CGFloat = 0
    private var skyClock: CGFloat = 0
    private var fogNode = SKNode()

    private var roadPool: [SKShapeNode] = []      // tan cells (procedural fallback)
    private var roadPoolB: [SKShapeNode] = []     // orange cells (procedural fallback)
    /// One shape per road tone per segment: the retail highway is a tiling of a
    /// few tones, so each segment's cells are bucketed by tone and every tone
    /// gets its own path. Empty when the retail art is missing, in which case
    /// the two-tone `roadPool`/`roadPoolB` checkerboard takes over.
    private var roadTonePool: [[SKShapeNode]] = []
    private let roadSurface: RetailAssets.TrackSurface?
    /// How much of the road's width one retail tile covers, and how many cells
    /// the tiling has on a side. The lattice is 32 cells square and half of it
    /// spans the highway, so sixteen cells lie across the road.
    private let roadTilesAcross: CGFloat = 0.5
    private let roadCellsAcross = 16
    /// How many points wide a road cell has to be before the tiling bothers to
    /// cut it out separately, and how tall a strip has to be before it is cut
    /// at a texture row. Below these the lattice is sub-pixel.
    private let detailMinCell: CGFloat = 3
    private let detailMinHeight: CGFloat = 4
    private var wallLeftPool: [SKShapeNode] = []
    private var wallRightPool: [SKShapeNode] = []
    /// The roadside rails a fence row stands up, one shape per rail drawn this
    /// frame. A rail is a quad that runs along the road rather than a billboard
    /// facing the camera, because that is what the build's `Barrier` object is:
    /// two 0.6-unit-tall, 9-unit-wide faces tiled with its own blue gradient.
    private var railPool: [SKShapeNode] = []
    private var railUse = 0
    /// When the rails stand. The `-norails` screenshot hook clears it, which
    /// leaves the fence posts of the procedural fallback standing instead.
    private var railsStand = true
    /// The strip that rail wears, and its height in the units the road is nine
    /// across. Both are nil/zero without the retail art, which leaves the
    /// fence posts of the procedural fallback standing.
    private lazy var railTexture: SKTexture? = railsStand ? Sprites.barrierGradient : nil
    private let railHeightUnits: CGFloat = 0.6
    /// Entities are pooled per kind. A turret also pools per size tier, because
    /// the build ships eight pillar meshes and one course can raise all of them.
    private struct EntityKey: Hashable {
        let kind: EntityKind
        let tier: Int
    }
    private var entityPool: [EntityKey: [SKNode]] = [:]
    private var entityUse: [EntityKey: Int] = [:]
    /// Idle bullets are pooled per weapon tier so an upgrade immediately swaps
    /// the look — a tier-1 pellet must never come back as a rocket.
    private var bulletPool: [Int: [SKNode]] = [:]
    private var bullets: [Bullet] = []
    /// Incoming bolts are pooled the same way, and kept apart from the snail's
    /// shots because they travel the other way down the road.
    private var enemyBulletPool: [SKNode] = []
    private var enemyBullets: [EnemyBullet] = []
    private var enemyFireTimer: CGFloat = 1.6

    // MARK: - Init

    init(mode: GameMode, level: Int, size: CGSize) {
        self.mode = mode
        self.level = level
        self.config = LevelConfig.forMode(mode, level: level)
        self.playerZ = cameraHeight * (1.0 / tan((100.0 / 2.0) * .pi / 180.0))
        let tint = UIColor(
            red: config.fringe.x / 255,
            green: config.fringe.y / 255,
            blue: config.fringe.z / 255,
            alpha: 1
        )
        self.fringe = tint
        if let wall = RetailAssets.fringeWall(tint) {
            let tex = SKTexture(image: wall)
            tex.filteringMode = .linear
            self.fringeWall = tex
        }
        let palette = RetailAssets.roadColours(track: config.track)
        self.roadOrange = palette.dark
        self.roadTan = palette.light
        self.roadSurface = RetailAssets.trackSurface(config.track)
        super.init(size: size)
        self.scaleMode = .resizeFill
        self.backgroundColor = UIColor(hex: backgroundHex(for: config.background))
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

#if DEBUG
    /// Screenshot hooks: `-weapon N` starts on ladder rung N (0...8) with
    /// autofire enabled.
    private func applyDebugArguments() {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-freeze"), i + 1 < args.count,
           let frames = Int(args[i + 1]) {
            framesToFreeze = frames
        }
        if let i = args.firstIndex(of: "-meterlock"), i + 1 < args.count,
           let pct = Double(args[i + 1]) {
            debugMeterLock = max(0, min(1, pct))
        }
        // `-norails` runs the course with the fence posts of the procedural
        // fallback in place of the blue rails, so a screenshot pair can show
        // what the rails cover.
        if args.contains("-norails") { railsStand = false }
        // `-nosnail` takes Turbo and his shadow off the road, so a screenshot
        // pair can measure exactly how wide he is drawn on his own row.
        if args.contains("-nosnail") {
            snail.isHidden = true
            childNode(withName: "snailshadow")?.isHidden = true
        }
        // `-lives N` banks spare shells, so the HUD's row of life icons can be
        // photographed lit without earning them a thousand points at a time.
        if let i = args.firstIndex(of: "-lives"), i + 1 < args.count,
           let count = Int(args[i + 1]) {
            state.lives = max(0, min(count, RaceState.maxLives))
        }
        // `-score N` starts the run with N points already on the board, so the
        // thousand-point life payouts (`0x4402a0`) can be watched landing on the
        // HUD without racing to them.
        if let i = args.firstIndex(of: "-score"), i + 1 < args.count,
           let points = Int(args[i + 1]) {
            state.sheet.bonus = points
        }
        guard let i = args.firstIndex(of: "-weapon"), i + 1 < args.count,
              let level = Int(args[i + 1]) else { return }
        state.weaponLevel = max(0, min(level, state.maxWeaponLevel))
        debugAutoFire = true
    }
#endif

    private func backgroundHex(for name: String) -> String {
        // Every level names a `BACKGROUNDS/*.txt` script, and each of those
        // declares the fog colour its backdrop is tinted with, so the sky is
        // read from the script's own `Fog:(r,g,b)` — the blue whirl, the green
        // warp, the purple and the red — rather than painted an invented
        // gradient. The scripts that ship without one all fog to the same
        // purple, so that is the fallback.
        guard let bg = TrackData.background[name.lowercased()] else { return "#800080" }
        return String(format: "#%02X%02X%02X", bg.fogR, bg.fogG, bg.fogB)
    }

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        // The race screen opens on the start line, so it carries the menu theme
        // until the snail actually sets off and the race track takes over.
        Sound.shared.playMusic(.menu)
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
            finish(won: true, handedOver: true)
        }
        if ProcessInfo.processInfo.arguments.contains("-pittest") {
            startRace()
            // Drop a pit directly under the snail so the fall can be watched.
            let idx = segmentIndex(at: positionZ + playerZ)
            segments[idx].sprites.removeAll { $0.kind == .hole }
            segments[idx].sprites.append(EntitySpec(kind: .hole, offset: 0, depth: 0.5))
        }
        if ProcessInfo.processInfo.arguments.contains("-fatal") {
            startRace()
            // Land a lethal blow on the start line, so the fatal hit can be
            // watched: with a spare shell banked the run goes on and the postal
            // meter refills, without one the race ends where it stands.
            damage(state.maxMeter + 1,
                   seg: segments[segmentIndex(at: positionZ + playerZ)])
        }
        if ProcessInfo.processInfo.arguments.contains("-paused") {
            startRace()
            // Hold the race on the start line, so the pause overlay `0x440640`
            // builds can be photographed.
            togglePause()
        }
        if let arg = ProcessInfo.processInfo.arguments.firstIndex(of: "-meter"),
           arg + 1 < ProcessInfo.processInfo.arguments.count,
           let pct = Double(ProcessInfo.processInfo.arguments[arg + 1]) {
            startRace()
            // Set the postal meter to a share of the full tube, so each of the
            // two pieces `0x4411b0` splits the tube into — the violet
            // `damageguage` above the health line and the pink
            // `damageguagefull` below it — can be photographed on its own.
            state.postalMeter = state.maxMeter * max(0, min(1, pct))
        }
        if ProcessInfo.processInfo.arguments.contains("-gaptop") {
            startRace()
            // Park the snail at the lip of the widest airborne gap so a jump
            // can be inspected without driving to one.
            if let widest = segments.max(by: { $0.gapRun < $1.gapRun }), widest.airborne {
                let mid = CGFloat(widest.gapStart + widest.gapRun / 2) * segmentLength
                positionZ = max(0, mid - playerZ - 10 * segmentLength)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-givesjet") {
            startRace()
            // Drop a jetpack under the snail so its flight can be watched
            // without relying on a piece's own pickup lane.
            let idx = segmentIndex(at: positionZ + playerZ)
            segments[idx].sprites.removeAll { $0.kind == .jetpack }
            segments[idx].sprites.append(EntitySpec(kind: .jetpack, offset: 0, depth: 0.5))
        }
        if ProcessInfo.processInfo.arguments.contains("-offroad") {
            startRace()
            // Carry the snail over the highway's edge, the way a shove does,
            // so the plunge off the side can be watched without waiting to be
            // knocked off by a highway pest.
            playerX = 1.15
            targetX = 1.15
        }
        if ProcessInfo.processInfo.arguments.contains("-offroadnf") {
            startRace()
            // The same, but over a row the piece tags `NoFall` — the trampoline
            // flights are the only rows that carry the tag off the void — so a
            // capture pair can show the tag holding the snail up where the
            // bare edge would drop it.
            if let idx = segments.firstIndex(where: { $0.noFall && !$0.airborne }) {
                positionZ = max(0, CGFloat(idx) * segmentLength - playerZ)
            }
            playerX = 1.15
            targetX = 1.15
        }
        debugIgnoreNoFall = ProcessInfo.processInfo.arguments.contains("-ignoretnf")
        let launchArgs = ProcessInfo.processInfo.arguments
        if let arg = launchArgs.firstIndex(of: "-turret"), arg + 1 < launchArgs.count,
           let tier = Int(launchArgs[arg + 1]) {
            startRace()
            // Keep a pillar of the given tier just ahead of the snail, so one of
            // the eight meshes can be looked at from close range without driving
            // a course that happens to spell that digit.
            debugTurretTier = tier
            parkDebugTurret()
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
        skyTiles = nil
        skyTileHeight = 0
        skyDistort = 0
        skyClock = 0
        let sky = SKNode()
        sky.name = "sky"
        sky.zPosition = -100

        // The retail build fills the sky with one of four tiled space textures
        // and scrolls it past the camera at the rate its `BACKGROUNDS/*.txt`
        // script's `Distort:` gives. Use the same art and the same rate.
        if let tex = RetailAssets.background(config.background) {
            buildRetailSky(into: sky, texture: tex)
            addChild(sky)
            return
        }

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
        var starRandom = CourseRandom(seed: sceneSeed)
        for _ in 0..<2 {
            let layer = SKNode()
            for _ in 0..<60 {
                let star = SKShapeNode(circleOfRadius: CGFloat.random(in: 0.8...2.4,
                                                                     using: &starRandom))
                star.fillColor = UIColor(white: 1, alpha: CGFloat.random(in: 0.3...0.95,
                                                                        using: &starRandom))
                star.strokeColor = .clear
                star.position = CGPoint(x: CGFloat.random(in: 0...size.width,
                                                          using: &starRandom),
                                        y: CGFloat.random(in: size.height * (1 - horizonRow)...size.height,
                                                          using: &starRandom))
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
        let fogBand = size.height * 0.5
        let fog = SKSpriteNode(texture: Sprites.gradientTexture(
            size: CGSize(width: 8, height: fogBand),
            colors: [fogColour.withAlphaComponent(0),
                     fogColour.withAlphaComponent(0.96),
                     fogColour.withAlphaComponent(0)],
            locations: [0, 0.5, 1]))
        fog.size = CGSize(width: size.width, height: fogBand)
        // Centred on the horizon, where the far highway dissolves into the sky.
        fog.position = CGPoint(x: size.width / 2, y: (1 - horizonRow) * size.height)
        fogNode.addChild(fog)
        addChild(fogNode)
    }

    /// The level's fog colour — the tint its `BACKGROUNDS/*.txt` script names.
    private var fogColour: UIColor { UIColor(hex: backgroundHex(for: config.background)) }

    /// Lays the level's own 512x256 space art over the scene — one copy, scaled
    /// to fill, which is what the retail build does.
    ///
    /// The art carries its own top-to-bottom gradient: a near-black ceiling that
    /// opens into the bright heart of the nebula. Retail frames of the purple
    /// route put the dark end above the camera and the bright end down behind
    /// the highway, with the horizon row landing on the art's own midtones, and
    /// a single fill-scaled copy reproduces that exactly. Tiling the art, as an
    /// earlier pass did, repeats the gradient down the screen and washes the
    /// whole sky out to the average of the nebula.
    private func buildRetailSky(into sky: SKNode, texture: SKTexture) {
        let art = texture.size()
        guard art.width > 0, art.height > 0 else { return }
        // Fill: the taller side sets the scale, the excess of the other is
        // cropped. The nebula is soft, so the crop costs nothing.
        let scale = max(size.width / art.width, size.height / art.height)
        let list = SKNode()
        let tile = SKSpriteNode(texture: texture)
        tile.size = CGSize(width: art.width * scale, height: art.height * scale)
        tile.position = CGPoint(x: size.width / 2, y: size.height / 2)
        list.addChild(tile)
        sky.addChild(list)

        skyTiles = list
        skyTileHeight = tile.size.height
        skyDistort = RetailAssets.backgroundDistort(config.background)
    }

    private func preparePools() {
        for i in 0..<drawDistance {
            if let surface = roadSurface {
                var row: [SKShapeNode] = []
                row.reserveCapacity(surface.palette.count)
                for tone in surface.palette {
                    let node = makeQuadNode(fill: tone, z: -CGFloat(i))
                    roadLayer.addChild(node)
                    row.append(node)
                }
                roadTonePool.append(row)
            } else {
                roadPool.append(makeQuadNode(fill: .black, z: -CGFloat(i)))
                roadPoolB.append(makeQuadNode(fill: .black, z: -CGFloat(i) + 0.05))
                roadLayer.addChild(roadPool[i])
                roadLayer.addChild(roadPoolB[i])
            }
            wallLeftPool.append(makeQuadNode(fill: .black, z: -CGFloat(i) + 0.1))
            wallRightPool.append(makeQuadNode(fill: .black, z: -CGFloat(i) + 0.1))
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
        snail.setScale(snailScale)
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
        state.weaponLevel = 0
        baseTargetSpeed = baseSpeed(for: config.speed)
        currentSpeed = baseTargetSpeed * 0.4
        positionZ = 0
        playerX = 0
        targetX = 0
        elapsed = 0
        boostUntil = 0
        invincibleUntil = 0
        hurtUntil = 0
        slugged = false
        timeUpAt = -1
        fallTimer = -1
        fallOffset = 0
        hopTimer = -1
        hopPower = 0
        gapFlight = -1
        gapArc = 0
        jetpackUntil = 0
        jetpackOffZ = 0
        tutorialStep = -1
        state.tutorialMessage = ""
        fireCooldown = 0
        clearBullets()
        clearEnemyBullets()
        enemyFireTimer = enemyFireInterval
        snail.setScale(snailScale)
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
        Sound.shared.playMusic(.race(config.track))
        Sound.shared.speak(.start)
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

    func steer(toFraction x: CGFloat) {
        let previous = targetX
        targetX = x
        // A hard swipe at speed scrubs the tyres — the original keeps a
        // dedicated `CameraSkidStop` model and `skidstop` sample for it.
        if state.phase == .running, elapsed >= skidUntil,
           abs(x - previous) > 0.5, currentSpeed > baseTargetSpeed * 0.8 {
            skidUntil = elapsed + 0.7
            Sound.shared.play(.skid)
        }
    }

    func setTouching(_ touching: Bool) { self.touching = touching }

    // MARK: - Update

    override func update(_ currentTime: TimeInterval) {
        defer { lastUpdate = currentTime }
        guard lastUpdate > 0 else { return }
        #if DEBUG
        // `-freeze N` runs N frames and then holds: the scene stops ticking, so
        // a screenshot taken seconds later still shows the same instant.
        if framesToFreeze >= 0 {
            if framesRun >= framesToFreeze {
                isPaused = true
                return
            }
            framesRun += 1
        }
        #endif
        // A frozen capture steps on a fixed clock: the race the Nth frame draws
        // then depends only on N, so two launches land on the same instant of
        // the same course instead of drifting apart with the machine's hitches.
        let dt = framesToFreeze >= 0 ? 1.0 / 60.0 : min(currentTime - lastUpdate, 1.0 / 30.0)
        let fdt = CGFloat(dt)

        #if DEBUG
        // `-meterlock F` holds the postal tube at a fraction of its length, so
        // one band of `0x4411b0` at a time — the wash it only reaches for above
        // 0.9, the violet and pink split — can be photographed without the race
        // draining the meter first.
        if let lock = debugMeterLock { state.postalMeter = state.maxMeter * lock }
        #endif
        scrollStars(fdt: fdt)
        scrollSky(fdt: fdt)
        // Turbo's animation rides the same clock, but a paused race holds its
        // pose; a finished one keeps playing so a loss can fall into its shell.
        frameDelta = state.phase == .paused ? 0 : fdt
        guard state.phase == .running else {
            // Paused or finished: the "going postal" alarm has nothing left to
            // warn about.
            Sound.shared.setPostalAlarm(false)
            renderRoad()
            return
        }

        elapsed += fdt
        state.elapsed = Double(elapsed)

        // The build's own fail-safe, whatever the mode: once the shared run
        // clock has been through its 21 000 frames it puts `Time's Up` on the
        // screen and ends the race on it (`0x43d1c8`).
        if timeUpAt < 0, elapsed >= timeLimit {
            timeUpAt = elapsed
            state.timedOut = true
        }
        if timeUpAt >= 0 {
            updateTimeUp(fdt: fdt)
            renderRoad()
            publish()
            return
        }

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
        updateRoadEdge()

        let move = currentSpeed * fdt
        positionZ += move
        state.distance = Double(positionZ)
        state.speed = Double(currentSpeed)
        updateTutorialScript()
        // The retail voice script asks for a line roughly every twenty seconds
        // (`Frequency:20`). Events supply most of them; `Misc` is the set for
        // the quiet stretches in between, so Turbo keeps a running commentary
        // when nothing in particular is happening. The tutorial's scripted
        // voice-over already fills those stretches, so it is left alone.
        if mode != .tutorial { Sound.shared.chatter() }

        if positionZ >= trackLength {
            positionZ = trackLength
            finish(won: state.quotaMet, handedOver: true)
            renderRoad()
            return
        }

        if touching || debugAutoFire {
            fireCooldown -= fdt
            if fireCooldown <= 0 {
                // The rung decides the pace, not the shot: a rung taken for
                // its faster timer really does fire faster.
                fireCooldown = CGFloat(state.weapon.fireInterval)
                fire()
            }
        }
        if hopTimer >= 0 {
            hopTimer += fdt
            if hopTimer >= hopDuration { hopTimer = -1 }
        }
        updateGapFlight()
        handleCollisions()
        updateInvincibility()
        updatePostalAlarm()
        #if DEBUG
        parkDebugTurret()
        #endif
        renderRoad()
        // Shots are moved and resolved against this frame's projections.
        updateBullets(fdt: fdt)
        updateEnemyFire(fdt: fdt)
        updateSkid(fdt: fdt)
        publish()
    }

    #if DEBUG
    /// Keeps the `-turret N` pillar a fixed number of segments ahead of the
    /// snail, re-parking it as he advances rather than leaving it on the start
    /// line, so a frozen capture always shows it from the same close range.
    private func parkDebugTurret() {
        guard let tier = debugTurretTier else { return }
        let ahead = 3 * segmentLength
        let idx = segmentIndex(at: positionZ + playerZ + ahead)
        guard idx != debugTurretSegment else { return }
        if let old = debugTurretSegment, old >= 0, old < segments.count {
            segments[old].sprites.removeAll { $0.kind == .turret }
        }
        segments[idx].sprites.removeAll { $0.kind == .turret }
        segments[idx].sprites.append(EntitySpec(kind: .turret, offset: 0,
                                                depth: 0.5, tier: tier))
        debugTurretSegment = idx
    }
    #endif

    private func updateSpeed(fdt: CGFloat) {
        var target = baseTargetSpeed
        if jetpackActive { target = baseTargetSpeed * 1.5 }
        else if elapsed < boostUntil { target = baseTargetSpeed * 1.4 }
        currentSpeed += (target - currentSpeed) * min(1, fdt * 0.7)
    }

    private func updateSteering(fdt: CGFloat) {
        playerX += (targetX - playerX) * min(1, fdt * 6)
        // Steering on its own stops at the edge: the touch range maps to
        // -1...1, which is the highway's own width. A shove from a hazard is
        // written to `targetX` past that, so the position is left free to
        // cross the line and `updateRoadEdge` decides whether that is a fall.
        playerX = max(-1.6, min(1.6, playerX))
    }

    /// The highway runs from -1 to 1 across, and its own edge is the tire line
    /// the ribbon ends on: a snail whose centre crosses that line has left the
    /// road. Nothing steers it out by itself, so only a shove — the highway
    /// pest's, or a fence's — carries it over, which is what the help screen
    /// means when it says they "knock you off the road". A row a piece tags
    /// `NoFall`, and a row it leaves airborne, are road the whole way out; the
    /// build marks those so a trampoline's bounce or a gap's arc cannot drop
    /// the snail that is still travelling over them.
    private func updateRoadEdge() {
        guard state.phase == .running, fallTimer < 0, hopTimer < 0 else { return }
        guard abs(playerX) > 1 else { return }
        guard !segments.isEmpty else { return }
        let seg = segments[segmentIndex(at: positionZ + playerZ)]
        guard !seg.airborne, debugIgnoreNoFall || !seg.noFall else { return }
        beginFall(offset: playerX)
    }

    /// The tutorial's warning that too much damage sends Turbo postal: the
    /// retail build loops its alarm while the meter is in the red and cuts it
    /// the moment a heart climbs the gauge back up.
    private func updatePostalAlarm() {
        Sound.shared.setPostalAlarm(state.meterFraction < 0.25)
    }

    private func scrollStars(fdt: CGFloat) {
        let speed = currentSpeed / max(baseTargetSpeed, 1)
        for (i, layer) in starLayers.enumerated() {
            let s = (i == 0 ? 20.0 : 60.0) * speed
            for star in layer.children {
                star.position.y -= CGFloat(s) * fdt
                if star.position.y < size.height * (1 - horizonRow) {
                    star.position.y = size.height + 4
                    star.position.x = CGFloat.random(in: 0...size.width, using: &sceneRandom)
                }
            }
        }
    }

    /// Let the retail backdrop breathe at the rate its level script asks for.
    ///
    /// The backdrop does not stream past the camera. Frame-to-frame comparisons
    /// of the retail captures land on a zero shift — holding the previous
    /// frame's sky against its successor matches best with no offset at all —
    /// so the sky stays put while the highway runs underneath it. The script's
    /// `Distort:` only puts a slow lateral swing into the nebula, and a level
    /// that asks for `Distort: 0` gets a backdrop that never moves.
    ///
    /// A swing rather than a one-way drift, so the copy never has to wrap and
    /// show a seam: the fastest sky takes a minute to cross and recross a
    /// twentieth of the screen, slower than a frame gap can resolve, which is
    /// why the retail captures read as still.
    ///
    /// Driven here rather than by an `SKAction`, which would run on the view's
    /// own clock: the original's sky is part of the world, so it has to hold
    /// still while a paused race does, and a frozen capture has to land on the
    /// same offset twice.
    private func scrollSky(fdt: CGFloat) {
        guard let tiles = skyTiles, skyTileHeight > 0, skyDistort > 0 else { return }
        skyClock += fdt
        let period = 1200 / Double(skyDistort)   // seconds for a full there-and-back
        let amplitude = size.width * skyDistort / 400
        tiles.position.x = amplitude * CGFloat(sin(skyClock / period * 2 * Double.pi))
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

    /// A vapour laser the highway pest has spat at the snail. It is placed on
    /// the road the same way the snail's shots are, but it runs the other way
    /// — z decreasing — so the two kinds of shot stay separate lists.
    private struct EnemyBullet {
        let node: SKNode
        var z: CGFloat
        var offset: CGFloat
        /// The lane the shot was aimed at. The bolt eases onto it as it comes,
        /// then holds it, so the snail can always step out of the way after the
        /// pest has fired.
        let target: CGFloat
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
                              level: state.weapon.shotClass,
                              z: positionZ + playerZ + muzzleAhead,
                              offset: playerX,
                              travel: 0,
                              lastPoint: .zero))
        Sound.shared.play(.shoot(state.weapon.shotClass))
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
                // A shot that lands far up the road covers a few pixels, so it
                // takes the small starburst; one on the snail is already scaled
                // up and takes the big one.
                spawnBurst(at: bullet.node.position, small: bullet.node.xScale < 0.55)
                if spec.kind == .slug { spawnGoo(at: bullet.node.position) }
                retireBullet(at: i)
                continue
            }

            if bullet.travel > bulletRange {
                retireBullet(at: i)
                continue
            }
            place(&bullet)
            // The rocket's warhead leaves a thinning trail of exhaust behind
            // it. Laid down every so many units of travel rather than every
            // frame, so the trail's grain does not change with the frame rate.
            if bullet.level >= 3,
               bullet.travel.truncatingRemainder(dividingBy: 24) < step {
                spawnSmoke(at: bullet.node.position,
                           width: 15 * max(0.3, bullet.node.xScale),
                           drift: CGPoint(x: 0, y: 4), life: 0.35)
            }
            bullets[i] = bullet
        }
    }

    /// The first shootable thing between two points along the track. The whole
    /// span is swept, so a shot can never tunnel through a target at speed.
    private func firstTarget(from z0: CGFloat, to z1: CGFloat,
                             offset: CGFloat) -> (RoadSegment, EntitySpec, CGFloat)? {
        guard !segments.isEmpty else { return nil }
        // Rockets carry a wider warhead than the blaster and the laser do.
        let reach: CGFloat = state.weapon.shotClass >= 3 ? 0.30 : 0.22
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
        case .slug:
            state.sheet.slug += 400
            // The snail's blaster is the only thing that kills a slug, so a
            // slug destroyed here was shot: give it its death rattle.
            Sound.shared.speakSlug(.killed)
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
                // A pit is as wide as it looks, and a turret widens with its
                // own mesh; everything else is a point-sized pick-up or hazard
                // with a slim footprint.
                let tolerance: CGFloat
                switch spec.kind {
                case .hole:
                    tolerance = (spec.width > 0 ? spec.width : holeHalfWidth * 2) / 2 * 0.93
                case .ramp:
                    // A ramp spans the columns its run covers, so a piece that
                    // turns the whole road into one (`{>>>>>>}`) launches the
                    // snail wherever it crosses, while a lone `<` at the kerb
                    // only catches a snail hugging that edge.
                    tolerance = max(0.16, spec.width * 0.93)
                case .turret:
                    tolerance = 0.16 * Sprites.pillarWidthFactor(spec.tier)
                default:
                    tolerance = 0.16
                }
                guard abs(spec.offset - playerX) < tolerance else { continue }
                switch spec.kind {
                case .parcel:
                    state.parcels += 1
                    state.sheet.parcelCollect += 100
                    Sound.shared.play(.collect)
                    Sound.shared.speak(.package)
                    toRemove.append((seg, spec))
                case .heart:
                    state.postalMeter = min(state.maxMeter, state.postalMeter + 25)
                    state.sheet.bonus += 100
                    Sound.shared.play(.heart)
                    toRemove.append((seg, spec))
                case .ringUpgrade:
                    // The power-up ring is the only way up the weapon ladder,
                    // and `0x4456d7` sets out exactly what it pays: one rung,
                    // a hundred points into the Parcel Collect tally (the same
                    // award a parcel makes), and the build's own power-up
                    // jingle with `pw1`...`pw7` indexed by the rung it just
                    // reached. The rung the snail stands on is what decides how
                    // hard and how fast he shoots from then on.
                    state.climbWeapon()
                    state.sheet.parcelCollect += 100
                    Sound.shared.play(.upgrade(state.weaponLevel))
                    Sound.shared.speak(.powerup)
                    toRemove.append((seg, spec))
                case .ringExplode:
                    // The yellow ring reaches out and pops every enemy around
                    // it, exactly as the tutorial describes.
                    detonateBlast()
                    state.sheet.ring += 200
                    Sound.shared.play(.explodeRing)
                    toRemove.append((seg, spec))
                case .ringSlow:
                    currentSpeed *= 0.6
                    Sound.shared.play(.slow)
                    Sound.shared.speak(.slow)
                    toRemove.append((seg, spec))
                case .salt:
                    damage(10, seg: seg)
                    toRemove.append((seg, spec))
                case .asteroid:
                    currentSpeed *= 0.5
                    damage(4, seg: seg, sound: .asteroid)
                    toRemove.append((seg, spec))
                case .slug:
                    // A slug takes a bite: the snail gives the slugged line and
                    // the slug gloats over it.
                    Sound.shared.speakSlug(.attack)
                    damage(12, seg: seg, bySlug: true)
                    toRemove.append((seg, spec))
                case .enemy:
                    guard !invincible else {
                        // Invincible: plough straight through the pest.
                        state.sheet.garbage += 200
                        toRemove.append((seg, spec))
                        continue
                    }
                    // The highway pest shoves the snail toward the edge of the
                    // road as well as denting the meter. The shove is written
                    // past the edge rather than clamped to it, so a snail
                    // already hugging that side is carried over and falls.
                    Sound.shared.speak(.enemies)
                    damage(14, seg: seg)
                    targetX = playerX + (playerX >= 0 ? 0.45 : -0.45)
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
                    if hopTimer < 0 && !jetpackActive {
                        beginFall(offset: spec.offset)
                    }
                case .ramp:
                    launch(power: 1.0, sound: .boost)
                case .trampoline:
                    launch(power: 1.5, sound: .trampoline)
                case .jetpack:
                    // The retail level hands the jetpack back with a
                    // `JetPackOff` piece a few segments later, so the flight
                    // lasts exactly as far as the gaps ahead instead of a
                    // fixed spell. A level with no such piece falls back to a
                    // short timed boost.
                    if let off = nextJetpackOffZ() {
                        jetpackOffZ = off
                        jetpackUntil = elapsed + 30
                    } else {
                        jetpackOffZ = 0
                        jetpackUntil = elapsed + 3.5
                    }
                    Sound.shared.play(.jetpack)
                    toRemove.append((seg, spec))
                case .ringNormal:
                    state.sheet.ring += 150
                    currentSpeed = min(baseTargetSpeed * 1.5,
                                       currentSpeed + baseTargetSpeed * 0.35)
                    Sound.shared.play(.highlight)
                    toRemove.append((seg, spec))
                case .arch:
                    break
                case .postOffice:
                    break
                case .signBang, .signConstruction, .signStop:
                    // Roadside scenery: the snail drives past it, and it
                    // never blocks or touches the road itself.
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

    private func damage(_ amount: Double, seg: RoadSegment, sound: Sound.Effect = .hit,
                        bySlug: Bool = false) {
        guard config.damageEnabled else { return }
        // Brief invulnerability after any hit. Fixed obstacles (holes, turrets)
        // stay on the road, so without this the snail would keep taking damage
        // every frame it overlapped one and die in an instant.
        guard !invincible else { return }
        invincibleUntil = elapsed + 0.75
        hurtUntil = elapsed + 0.3
        state.postalMeter = max(0, state.postalMeter - amount)
        Sound.shared.play(sound)
        if state.postalMeter <= 0 {
            // A banked spare shell buys the snail another go on the road.
            if revive(bySlug: bySlug) { return }
            // A fatal hit is the snail's last word, not one complaint stacked
            // on another: skip the hurt grunt and let `finish` say the dying
            // line — `Slugged` when a slug landed the killing blow.
            if bySlug {
                slugged = true
                Sound.shared.speakSlug(.gloat)
            }
            finish(won: false, signOff: bySlug ? .slugged : .dying)
            return
        }
        // The retail snail complains when it is hurt; its voice script makes
        // `Ouch` a subset of the same complaint set.
        Sound.shared.speak(amount >= 10 ? .damage : .ouch)
    }

    /// Spends a banked spare shell after a fatal hit. While a life is left the
    /// snail goes back on the road with a full postal meter and a moment of
    /// mercy invincibility, and only the last life ends the run — the question
    /// the retail build asks of its `0x4340` counter at `0x446e25`. Returns
    /// whether the run goes on.
    private func revive(bySlug: Bool) -> Bool {
        guard state.spendLife() else { return false }
        state.postalMeter = state.maxMeter
        hurtUntil = 0
        invincibleUntil = elapsed + 2
        // The dying line still belongs to the death that was survived, with the
        // slug's own gloat over the top when it landed the blow.
        Sound.shared.speak(bySlug ? .slugged : .dying)
        if bySlug { Sound.shared.speakSlug(.gloat) }
        publish()
        return true
    }

    // MARK: - Falling into a hole

    /// Show the tutorial's scripted line for the furthest piece it has reached.
    /// The level file lists one line per segment in the order it lays them, so
    /// the snail walking the track walks the script: a piece that carries no
    /// line of its own (`Tutorial 4.txt` appears twice in a row) leaves the
    /// last line up until the next one arrives.
    private func updateTutorialScript() {
        let script = TrackData.tutorialScript
        guard mode == .tutorial, !script.isEmpty, !segments.isEmpty else { return }
        let step = segments[segmentIndex(at: positionZ + playerZ)].script
        guard step >= 0 && step < script.count && step > tutorialStep else { return }
        tutorialStep = step
        let line = script[step]
        if !line.isEmpty { state.tutorialMessage = line }
        // The retail build speaks each line as the piece arrives.  The
        // script names the recording, so play it by name; the empty lines
        // carry no voice.
        if step < TrackData.tutorialVoice.count,
           let voice = TrackData.tutorialVoice[step] {
            Sound.shared.speak(tutorialLine: voice)
        }
    }

    /// The jump pieces leave the road out for a run of blank rows. The snail
    /// takes that void as a ramp and arcs across it, the same screen-space hop
    /// the ramps and trampolines use but stretched to span the whole gap. It
    /// keeps steering the whole way, which is the whole point of a gauntlet
    /// like `Easy Gap`: its meteors are floating in the void to be dodged.
    private func updateGapFlight() {
        guard !segments.isEmpty else { return }
        let z = positionZ + playerZ
        let seg = segments[segmentIndex(at: z)]
        guard seg.airborne, seg.gapRun > 0 else {
            gapFlight = -1
            return
        }
        if gapFlight < 0 {
            // Boarding the gap: measure the arc from the near lip of the void,
            // so a frame that lands mid-run still draws a smooth parabola.
            gapStartZ = CGFloat(seg.gapStart) * segmentLength
            gapLengthZ = CGFloat(seg.gapRun) * segmentLength
            gapArc = min(150, 46 + CGFloat(seg.gapRun) * 5)
            if seg.gapRun >= 6 {
                Sound.shared.play(.boost)
                Sound.shared.speak(.wormTunnel)
            }
        }
        var dz = (z - gapStartZ).truncatingRemainder(dividingBy: max(trackLength, 1))
        if dz < 0 { dz += max(trackLength, 1) }
        gapFlight = max(0, min(1, dz / max(gapLengthZ, 1)))
    }

    /// Fly off a ramp or trampoline: a short hop that clears pits and hazards,
    /// with a burst of speed for the landing.
    private func launch(power: CGFloat, sound: Sound.Effect) {
        guard fallTimer < 0, hopTimer < 0 else { return }
        hopTimer = 0
        hopPower = power
        invincibleUntil = max(invincibleUntil, elapsed + hopDuration + 0.15)
        currentSpeed = min(baseTargetSpeed * 1.6,
                           currentSpeed + baseTargetSpeed * 0.5 * power)
        boostUntil = max(boostUntil, elapsed + 0.5)
        Sound.shared.play(sound)
        Sound.shared.speak(.superTramp)
    }

    /// Drop the snail into a pit. Contact damage is suppressed while falling —
    /// the plunge itself is the punishment, and it is applied on the way out.
    private func beginFall(offset: CGFloat) {
        guard fallTimer < 0, state.phase == .running else { return }
        fallTimer = 0
        fallOffset = offset
        gapFlight = -1
        clearBullets()
        clearEnemyBullets()
        Sound.shared.play(.fall)
        Sound.shared.speak(.fall)
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

        snail.setScale(snailScale)
        snail.zRotation = 0
        snail.alpha = 1

        if config.damageEnabled {
            state.postalMeter = max(0, state.postalMeter - 16)
            Sound.shared.play(.hit)
            hurtUntil = elapsed + 0.3
            if state.postalMeter <= 0 {
                if revive(bySlug: false) { return }
                finish(won: false)
                return
            }
        }
        invincibleUntil = elapsed + 1.4
    }

    /// The fail-safe's own three seconds. The build draws `Time's Up` over the
    /// road, lets its ramp climb to full and only then tears the line down and
    /// ends the race (`0x445e00`); the snail coasts to a stop under it.
    private func updateTimeUp(fdt: CGFloat) {
        currentSpeed = max(0, currentSpeed - fdt * 9000)
        state.speed = Double(currentSpeed)
        positionZ = min(trackLength, positionZ + currentSpeed * fdt)
        state.distance = Double(positionZ)
        if elapsed - timeUpAt >= timeUpHold { finish(won: false) }
    }

    private func updateInvincibility() {
        state.invincible = invincible
    }

    /// Tyres scrubbing the road through a hard drag. The retail build keeps a
    /// dedicated `skidstop` pose for the moment, and this lays the smoke that
    /// goes with it on the road behind the snail.
    private func updateSkid(fdt: CGFloat) {
        guard elapsed < skidUntil else {
            skidClock = 0
            return
        }
        skidClock -= fdt
        guard skidClock <= 0 else { return }
        skidClock = 0.055
        // He is drawn at his own road point with his tail toward the camera, so
        // the puff starts under him and drifts further down the screen.
        let outward = targetX - playerX
        spawnSmoke(at: CGPoint(x: snail.position.x - outward * 26,
                               y: snail.position.y + 6),
                   width: 26,
                   drift: CGPoint(x: -outward * 26, y: -14),
                   life: 0.4)
    }

    // MARK: - Bullets

    private func obtainBullet() -> SKNode {
        // Shots are pooled by the mesh they wear, which is what the rung's
        // mask picks, so a snail carrying a rocket never draws a pellet.
        let level = state.weapon.shotClass
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

    // MARK: - Enemy return fire

    /// The highway pest shoots back. Every so often the nearest pest ahead of
    /// the snail spits a vapour laser down the road, so the player has to weave
    /// as well as ram. Each bolt is aimed at the lane the snail was in when it
    /// was fired, which keeps it dangerous without making it impossible to step
    /// out of the way.
    private func updateEnemyFire(fdt: CGFloat) {
        enemyFireTimer -= fdt
        if enemyFireTimer <= 0 {
            enemyFireTimer = enemyFireInterval
            fireFromEnemyAhead()
        }

        guard !enemyBullets.isEmpty else { return }
        let player = positionZ + playerZ
        // Bolts close on the snail from both directions at once: they fly
        // toward the camera while the snail drives up the road at them.
        let step = max(currentSpeed, baseTargetSpeed) * enemyBulletSpeedFactor * fdt
        for i in enemyBullets.indices.reversed() {
            var bolt = enemyBullets[i]
            let previous = bolt.z
            bolt.z -= step
            bolt.offset += (bolt.target - bolt.offset) * min(1, fdt * 4)

            // A bolt covers more ground in one frame than the snail is wide, so
            // test the crossing of the snail's own plane rather than a window
            // around it — a window lets a fast bolt tunnel straight through.
            let crossed = previous >= player && bolt.z <= player
            if crossed, abs(bolt.offset - playerX) < 0.16 {
                spawnBurst(at: bolt.node.position)
                damage(14, seg: segments[segmentIndex(at: player)])
                retireEnemyBullet(at: i)
                continue
            }
            // Once it is past the camera plane the projection stops placing it,
            // so retire it a little beyond that rather than letting the list
            // grow behind the snail.
            if bolt.z < positionZ - segmentLength {
                retireEnemyBullet(at: i)
                continue
            }
            placeEnemyBullet(&bolt)
            enemyBullets[i] = bolt
        }
    }

    /// Opens fire from the nearest pest the snail is closing on. Only the
    /// closest one shoots, so a road thick with pests cannot hose the screen.
    private func fireFromEnemyAhead() {
        guard !segments.isEmpty else { return }
        let base = segmentIndex(at: positionZ + playerZ)
        for d in 2...enemyFireRange {
            let seg = segments[(base + d) % segments.count]
            guard let spec = seg.sprites.first(where: { $0.kind == .enemy }) else { continue }
            let node = obtainEnemyBullet()
            node.isHidden = false
            node.alpha = 1
            node.setScale(1)
            node.zRotation = 0
            enemyBullets.append(EnemyBullet(node: node,
                                            z: CGFloat(base + d) * segmentLength,
                                            offset: spec.offset,
                                            target: playerX,
                                            lastPoint: .zero))
            Sound.shared.play(.enemyFire)
            return
        }
    }

    /// Moves an incoming bolt to its place on the road, growing as it closes on
    /// the camera and swinging to point the way it travels.
    private func placeEnemyBullet(_ bolt: inout EnemyBullet) {
        guard let p = roadPoint(z: bolt.z, offset: bolt.offset) else {
            bolt.node.isHidden = true
            return
        }
        bolt.node.isHidden = false
        bolt.node.position = p.point
        let muzzleHalfWidth = size.width * 0.5
        let taper = muzzleHalfWidth > 0 ? p.halfWidth / muzzleHalfWidth : 0
        bolt.node.setScale(min(1.2, max(0.12, taper * 1.2)))
        if bolt.lastPoint != .zero {
            let dx = p.point.x - bolt.lastPoint.x
            let dy = p.point.y - bolt.lastPoint.y
            if abs(dx) + abs(dy) > 0.5 {
                bolt.node.zRotation = atan2(dy, dx)
            }
        }
        bolt.lastPoint = p.point
    }

    private func obtainEnemyBullet() -> SKNode {
        if let node = enemyBulletPool.popLast() { return node }
        let node = Sprites.makeEnemyBullet()
        node.zPosition = 24
        fxLayer.addChild(node)
        return node
    }

    private func retireEnemyBullet(at index: Int) {
        let bolt = enemyBullets.remove(at: index)
        bolt.node.isHidden = true
        bolt.node.alpha = 1
        bolt.node.setScale(1)
        enemyBulletPool.append(bolt.node)
    }

    private func clearEnemyBullets() {
        for i in enemyBullets.indices.reversed() { retireEnemyBullet(at: i) }
    }

    /// The pop of a hit: the build's own starburst thrown from the impact
    /// point, grown as it fades, with a few of its sparkles tumbling out of it.
    /// The installer draws the starburst at two sizes, so a hit resolved far up
    /// the road takes the small one rather than a blast-sized flash that would
    /// read as if it landed on the bonnet.
    private func spawnBurst(at point: CGPoint, small: Bool = false) {
        if let flash = Sprites.makeParticle(small ? "particleexplode-small"
                                                  : "particleexplode-big",
                                            width: small ? 26 : 74) {
            flash.position = point
            flash.zPosition = 26
            flash.zRotation = CGFloat.random(in: 0...(2 * .pi), using: &sceneRandom)
            fxLayer.addChild(flash)
            flash.run(.sequence([
                .group([.scale(to: 1.8, duration: 0.26), .fadeOut(withDuration: 0.26)]),
                .removeFromParent(),
            ]))
        }
        spawnSparks(at: point, count: small ? 3 : 6, spread: small ? 11 : 27)
    }

    /// A handful of the build's four-point sparkles flying out of a hit.
    private func spawnSparks(at point: CGPoint, count: Int, spread: CGFloat) {
        guard count > 0 else { return }
        for i in 0..<count {
            guard let spark = Sprites.makeParticle("spark", width: 13) else { return }
            let angle = CGFloat(i) / CGFloat(count) * 2 * .pi
                + CGFloat.random(in: -0.4...0.4, using: &sceneRandom)
            let reach = spread * CGFloat.random(in: 0.7...1.3, using: &sceneRandom)
            spark.position = point
            spark.zPosition = 26
            fxLayer.addChild(spark)
            spark.run(.sequence([
                .group([.moveBy(x: cos(angle) * reach, y: sin(angle) * reach, duration: 0.3),
                        .scale(to: 0.4, duration: 0.3),
                        .fadeOut(withDuration: 0.3)]),
                .removeFromParent(),
            ]))
        }
    }

    /// A puff of the build's smoke, for tyres scrubbing the road and for the
    /// exhaust trailing a shot.
    private func spawnSmoke(at point: CGPoint, width: CGFloat,
                            drift: CGPoint = .zero, life: TimeInterval = 0.45) {
        guard let puff = Sprites.makeParticle("smoke", width: width, alpha: 0.8) else { return }
        puff.position = point
        puff.zPosition = 24
        puff.zRotation = CGFloat.random(in: 0...(2 * .pi), using: &sceneRandom)
        fxLayer.addChild(puff)
        puff.run(.sequence([
            .group([.moveBy(x: drift.x, y: drift.y, duration: life),
                    .scale(to: 1.9, duration: life),
                    .fadeOut(withDuration: life)]),
            .removeFromParent(),
        ]))
    }

    /// What a slug leaves where it was shot.
    private func spawnGoo(at point: CGPoint) {
        guard let goo = Sprites.makeParticle("sluggoo", width: 26, alpha: 0.95) else { return }
        goo.position = point
        goo.zPosition = 25
        goo.zRotation = CGFloat.random(in: 0...(2 * .pi), using: &sceneRandom)
        fxLayer.addChild(goo)
        goo.run(.sequence([
            .group([.scale(to: 1.6, duration: 0.5), .fadeOut(withDuration: 0.5)]),
            .removeFromParent(),
        ]))
    }

    // MARK: - Rendering

    /// The projection math is done in canvas space (y grows downward, like the
    /// classic pseudo-3D racer). SpriteKit's y axis points up, so flip when we
    /// actually place geometry.
    private func fy(_ y: CGFloat) -> CGFloat { size.height - y }

    /// Which of the retail build's Turbo clips he should be playing. The ones
    /// that mark a moment — the plunge, the shell, a hit, a skid — outrank the
    /// two that run while he is simply travelling, so a hit is never hidden
    /// behind the cruising loop.
    private func snailClip() -> String {
        if fallTimer >= 0 { return "fall" }
        if slugged { return "intoshell" }
        if elapsed < hurtUntil { return "damaged" }
        if elapsed < skidUntil { return "skidstop" }
        if hopTimer >= 0 { return "bobalong" }
        if gapFlight >= 0 { return targetX < 0 ? "lookbackleft" : "lookbackright" }
        if invincible { return "invincible" }
        return currentSpeed < baseTargetSpeed * 0.4 ? "base" : "move"
    }

    private func renderRoad() {
        for i in 0..<railUse where i < railPool.count { railPool[i].isHidden = true }
        railUse = 0
        for i in 0..<drawDistance {
            if i < roadPool.count { roadPool[i].isHidden = true }
            if i < roadPoolB.count { roadPoolB[i].isHidden = true }
            for node in roadTonePool[i] { node.isHidden = true }
            wallLeftPool[i].isHidden = true
            wallRightPool[i].isHidden = true
        }
        for value in entityUse.keys { entityUse[value] = 0 }

        let baseSegment = segments[segmentIndex(at: positionZ)]
        let basePercent = percentRemaining(positionZ, segmentLength)
        let playerSeg = segments[segmentIndex(at: positionZ + playerZ)]
        let playerPercent = percentRemaining(positionZ + playerZ, segmentLength)
        let playerY = interpolate(playerSeg.p1.world.y, playerSeg.p2.world.y, playerPercent)
        let playerRoll = interpolate(playerSeg.roll, playerSeg.rollEnd, playerPercent)

        var maxy = size.height
        var x: CGFloat = 0
        var dx: CGFloat = -(baseSegment.curve * basePercent)
        // The row Turbo rides on, in the projection's own y-grows-downwards
        // canvas space. His size is read off the highway here.
        let snailRow = size.height * 0.83

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
            drawRails(seg, n: n)
            if seg.p1.screenY >= snailRow && seg.p2.screenY <= snailRow {
                let span = max(0.0001, seg.p1.screenY - seg.p2.screenY)
                let t = (seg.p1.screenY - snailRow) / span
                snailRowHalfWidth = interpolate(seg.p1.screenW, seg.p2.screenW, t)
            }
            maxy = seg.p2.screenY
        }

        renderEntities(baseSegment: baseSegment)

        // Player.
        // Turbo is scaled against the highway on his own row, not against the
        // screen, so a tall portrait phone does not inflate him.
        let halfRoad = snailRowHalfWidth > 0 ? snailRowHalfWidth : size.width * 0.48
        snailScale = max(0.05, halfRoad * 2 * snailRoadFraction / Sprites.snailNativeWidth)
        if fallTimer >= 0 {
            // Tumbling down the pit: sink below the road, spin and shrink.
            let p = min(1, fallTimer / fallDuration)
            let ease = p * p
            snail.position = CGPoint(x: size.width * 0.5,
                                     y: size.height * 0.17 - 95 * ease * snailScale)
            snail.zRotation = p * 5.6
            snail.setScale(snailScale * (1 - 0.5 * ease))
            snail.alpha = 1 - 0.3 * p
        } else {
            snail.position = CGPoint(x: size.width * 0.5, y: size.height * 0.17)
            // Steer with the road, then add the roll of a loop or a screw so
            // the snail actually turns over as it flies the piece.
            snail.zRotation = -playerX * 0.22 + playerRoll
            snail.setScale(snailScale)
            Sprites.setBoost(snail, on: elapsed < boostUntil || jetpackActive
                             || currentSpeed > baseTargetSpeed * 1.05)
            Sprites.setSnailGear(snail, weapon: state.weapon.shotClass, jetpack: jetpackActive,
                                 invincible: invincible, dt: frameDelta)
            // Blink while the post-hit invulnerability is active.
            snail.alpha = elapsed < invincibleUntil ? 0.45 + 0.55 * abs(sin(elapsed * 22)) : 1
            Sprites.setSnailClip(snail, snailClip(), dt: frameDelta)
            snail.position.y += sin(elapsed * 14) * 2
            // Riding a ramp: arc the snail up and over the road.
            if hopTimer >= 0 {
                let p = hopTimer / hopDuration
                snail.position.y += sin(p * .pi) * 70 * hopPower
                snail.zRotation += sin(p * .pi) * 0.3 * hopPower
            }
            // Flying a gap: the arc grows with the void, so a stepping stone
            // barely lifts the snail while a `Huge Gap` throws it right up.
            if gapFlight >= 0 {
                let p = gapFlight
                snail.position.y += sin(p * .pi) * gapArc
                snail.zRotation += sin(p * .pi) * 0.3
            }
        }
        if let shadow = childNode(withName: "snailshadow") {
            shadow.setScale(snailScale)
            shadow.position = CGPoint(x: snail.position.x,
                                      y: snail.position.y - 34 * snailScale)
            shadow.zRotation = snail.zRotation
            shadow.alpha = fallTimer >= 0 ? max(0, 1 - fallTimer / fallDuration) : 1
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-snailprobe") {
            let f = snail.calculateAccumulatedFrame()
            let body = (snail.childNode(withName: "snailframes") as? SKSpriteNode)?
                .calculateAccumulatedFrame()
            print("SNAILPROBE scale=\(snailScale) node w=\(f.width) h=\(f.height)"
                  + " body w=\(body?.width ?? 0) h=\(body?.height ?? 0)"
                  + " centre=(\(f.midX),\(f.midY)) scene=\(size.width)x\(size.height)"
                  + " half=\(snailRowHalfWidth)")
        }
        // `-edgeprobe`: print where the snail sits against the highway's edge
        // and whether a fall has started, so the edge rule can be read off a
        // run instead of compared between two screenshots.
        if ProcessInfo.processInfo.arguments.contains("-edgeprobe") {
            let row = segments.isEmpty ? -1 : segmentIndex(at: positionZ + playerZ)
            let seg = row >= 0 ? segments[row] : nil
            if framesToFreeze >= 0 && framesRun >= framesToFreeze {
                print("EDGEPROBE frame=\(framesRun) x=\(playerX) target=\(targetX)"
                      + " fall=\(fallTimer) row=\(row) noFall=\(seg?.noFall ?? false)"
                      + " air=\(seg?.airborne ?? false)")
            }
        }
        #endif
    }

    private func drawSegment(_ seg: RoadSegment, n: Int) {
        // An airborne slice is the void a jump flies over: no tiles, no
        // fringe walls, just the background scrolling past underneath.
        guard !seg.airborne else { return }

        if let surface = roadSurface {
            drawTiledRoad(seg, n: n, surface: surface)
            drawFringe(seg, n: n)
            return
        }

        // The retail highway is a tiling texture -- a diamond lattice in the two
        // tones `Track:` selects (sand, grass, ice, violet). SpriteKit cannot map
        // a texture across a shape's fill, so the same lattice is rebuilt as a
        // checkerboard of column cells whose parity alternates with depth as
        // well as across the road, using the retail palette.
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
        roadPool[n].fillColor = roadTan
        roadPool[n].path = evenPath
        roadPoolB[n].isHidden = oddPath.isEmpty
        roadPoolB[n].fillColor = roadOrange
        roadPoolB[n].path = oddPath

        drawFringe(seg, n: n)
    }

    /// The road with the retail tiling read back in. Each segment is cut where
    /// the texture's cell grid crosses it and across the road into one cell per
    /// texture column; every cell takes the tone of the texture cell it covers
    /// and is added to that tone's path, so a whole segment costs one shape per
    /// tone rather than one per cell.
    private func drawTiledRoad(_ seg: RoadSegment, n: Int,
                               surface: RetailAssets.TrackSurface) {
        let tones = roadTonePool[n]
        guard !tones.isEmpty else { return }

        let l1 = seg.p1.screenX - seg.p1.screenW, r1 = seg.p1.screenX + seg.p1.screenW
        let l2 = seg.p2.screenX - seg.p2.screenW, r2 = seg.p2.screenX + seg.p2.screenW
        let y1 = fy(seg.p1.screenY), y2 = fy(seg.p2.screenY)
        guard r1 > l1 || r2 > l2 else { return }

        let blocks = CGFloat(surface.blocks)
        // One tile of the texture is `roadTileWorld` across in world units, and
        // the lattice is square, so the same figure measures depth.
        let tileWorld = 2 * roadWidth / roadTilesAcross
        let v1 = CGFloat(seg.index) * segmentLength / tileWorld
        let v2 = v1 + segmentLength / tileWorld
        let dv = v2 - v1

        // Cut the segment at every texture row boundary it crosses.
        var cuts: [CGFloat] = [0, 1]
        if dv > 0 && abs(y2 - y1) >= detailMinHeight {
            var m = Int(floor(v1 * blocks)) + 1
            while CGFloat(m) / blocks < v2 {
                let t = (CGFloat(m) / blocks - v1) / dv
                if t > 0 && t < 1 { cuts.append(t) }
                m += 1
            }
        }
        cuts.sort()

        // A texture cell that lands on less than a couple of points cannot be
        // told apart from its neighbours, so a thin sliver near the horizon is
        // drawn as one cell instead of sixteen. Only the strips close to the
        // camera carry the lattice.
        let span = max(r1 - l1, r2 - l2)
        let cellsAcross = max(1, min(roadCellsAcross,
                                     Int((span / detailMinCell).rounded())))

        // Cells overlap by a fraction of a point so the seams between them do
        // not show as hairlines against the sky.
        let bleed: CGFloat = 0.4
        var paths = [CGMutablePath?](repeating: nil, count: tones.count)

        for ci in 0..<(cuts.count - 1) {
            let ta = cuts[ci], tb = cuts[ci + 1]
            guard tb - ta > 0.0001 else { continue }
            let tm = (ta + tb) / 2
            let by = Int(floor((v1 + dv * tm) * blocks))
            let ay0 = y1 + (y2 - y1) * ta - bleed
            let ay1 = y1 + (y2 - y1) * tb + bleed
            let ax0L = l1 + (l2 - l1) * ta, ax0R = r1 + (r2 - r1) * ta
            let ax1L = l1 + (l2 - l1) * tb, ax1R = r1 + (r2 - r1) * tb

            for c in 0..<cellsAcross {
                let f0 = CGFloat(c) / CGFloat(cellsAcross)
                let f1 = CGFloat(c + 1) / CGFloat(cellsAcross)
                // The texture columns this cell covers: the last one is
                // inclusive, so a cell that still has full detail samples the
                // single column it lands on.
                let bx0 = Int(floor(f0 * roadTilesAcross * blocks))
                let bx1 = max(bx0, Int(ceil(f1 * roadTilesAcross * blocks)) - 1)
                let tone = bx1 > bx0
                    ? surface.meanTone(fromBlockX: bx0, toBlockX: bx1, blockY: by)
                    : surface.toneIndex(blockX: bx0, blockY: by)
                guard tone < tones.count else { continue }

                let p: CGMutablePath
                if let existing = paths[tone] { p = existing } else {
                    let made = CGMutablePath()
                    paths[tone] = made
                    p = made
                }
                let a0 = ax0L + (ax0R - ax0L) * f0
                let a1 = ax0L + (ax0R - ax0L) * f1
                let b0 = ax1L + (ax1R - ax1L) * f0
                let b1 = ax1L + (ax1R - ax1L) * f1
                let g: CGFloat = 0.4
                p.move(to: CGPoint(x: min(a0, b0) - g, y: ay0))
                p.addLine(to: CGPoint(x: max(a1, b1) + g, y: ay0))
                p.addLine(to: CGPoint(x: max(a1, b1) + g, y: ay1))
                p.addLine(to: CGPoint(x: min(a0, b0) - g, y: ay1))
                p.closeSubpath()
            }
        }

        for (tone, node) in tones.enumerated() {
            if let path = paths[tone] {
                node.path = path
                node.isHidden = false
            }
        }
    }

    private func drawFringe(_ seg: RoadSegment, n: Int) {
        // The walls on both sides of the highway, tinted with the level's
        // `Fringe:` colour and filled with the retail gradient, so each wall is
        // solid where it meets the road and fades out as it rises.
        let lh1 = seg.p1.screenW * wallRatio
        let lh2 = seg.p2.screenW * wallRatio
        let lx1 = seg.p1.screenX - seg.p1.screenW
        let lx2 = seg.p2.screenX - seg.p2.screenW
        let rx1 = seg.p1.screenX + seg.p1.screenW
        let rx2 = seg.p2.screenX + seg.p2.screenW

        wallLeftPool[n].isHidden = false
        wallLeftPool[n].fillColor = fringeWall == nil ? fringe : .white
        wallLeftPool[n].fillTexture = fringeWall
        wallLeftPool[n].path = quad(lx1, fy(seg.p1.screenY), lx1, fy(seg.p1.screenY - lh1),
                                    lx2, fy(seg.p2.screenY - lh2), lx2, fy(seg.p2.screenY))
        wallRightPool[n].isHidden = false
        wallRightPool[n].fillColor = fringeWall == nil ? fringe : .white
        wallRightPool[n].fillTexture = fringeWall
        wallRightPool[n].path = quad(rx1, fy(seg.p1.screenY), rx1, fy(seg.p1.screenY - lh1),
                                     rx2, fy(seg.p2.screenY - lh2), rx2, fy(seg.p2.screenY))
    }

    private let checkCols = 6

    /// The blue rails the highway wears.
    ///
    /// `Objects/Barrier` is not a prop but a length of guard rail: two faces
    /// 0.6 units tall, 4.5 either side of its origin — the highway's own half
    /// width — running 58 units along the road. Every row of every piece marks
    /// where it stands with an `@` in the outer two columns, and the tutorial
    /// says what it is for: "The blue barriers prevent me from falling off the
    /// sides of the highway." So both sides are railed for the whole course,
    /// and every other barrier cell in the grid stands the same rail a lane
    /// further in — the rails of a bridge run its edges, a chicane's pair pinch
    /// it in, and the pieces of a fence row leave the lanes between them to
    /// thread.
    private func drawRails(_ seg: RoadSegment, n: Int) {
        guard let rail = railTexture, !seg.airborne else { return }
        let y1 = fy(seg.p1.screenY), y2 = fy(seg.p2.screenY)
        let h1 = railHeight(at: seg.p1.screenW), h2 = railHeight(at: seg.p2.screenW)
        // Past this the rail is under a point tall, and the road carrying it is
        // a few wide: a shape there is invisible either way, so the horizon is
        // spared the nodes.
        guard h2 > 1 else { return }
        for side in [CGFloat(-1), 1] {
            standRail(rail, n: n,
                      seg.p1.screenX + side * seg.p1.screenW, y1, h1,
                      seg.p2.screenX + side * seg.p2.screenW, y2, h2)
        }
        for spec in seg.sprites where spec.kind == .barrier {
            standRail(rail, n: n,
                      seg.p1.screenX + spec.offset * seg.p1.screenW, y1, h1,
                      seg.p2.screenX + spec.offset * seg.p2.screenW, y2, h2)
        }
    }

    /// How tall a rail stands at a row whose half-highway measures `halfRoad`
    /// points, in the points the canvas is drawn in.
    ///
    /// `halfRoad` is half the nine units the road is across, so a model unit
    /// laid across it is `2 * halfRoad / roadModelWidth` points. A unit stood
    /// on end is the same: everything the course stands up — the fringe wall,
    /// a pillar, the snail — is drawn from its own width, so the road's own
    /// scale is what puts it on screen.
    private func railHeight(at halfRoad: CGFloat) -> CGFloat {
        halfRoad * 2 / roadModelWidth * railHeightUnits
    }

    /// One length of rail, from `x1`/`y1` to `x2`/`y2` and standing `h` points
    /// above the road at each end.
    private func standRail(_ rail: SKTexture, n: Int,
                           _ x1: CGFloat, _ y1: CGFloat, _ h1: CGFloat,
                           _ x2: CGFloat, _ y2: CGFloat, _ h2: CGFloat) {
        let node = obtainRail()
        node.path = quad(x1, y1, x1, y1 + h1, x2, y2 + h2, x2, y2)
        node.fillTexture = rail
        node.zPosition = -CGFloat(n) + 0.2
        node.isHidden = false
    }

    private func obtainRail() -> SKShapeNode {
        if railUse < railPool.count {
            let node = railPool[railUse]
            railUse += 1
            return node
        }
        let node = SKShapeNode()
        // White, so the gradient texture arrives unmultiplied.
        node.fillColor = .white
        node.strokeColor = .clear
        node.lineWidth = 0
        node.isAntialiased = false
        node.isHidden = true
        railPool.append(node)
        roadLayer.addChild(node)
        railUse += 1
        return node
    }

    private func renderEntities(baseSegment: RoadSegment) {
        let baseIndex = baseSegment.index
        for n in 1..<drawDistance {
            let seg = segments[(baseIndex + n) % segments.count]
            guard !seg.sprites.isEmpty else { continue }
            let p = seg.p1
            guard p.scale > 0, !p.screenW.isNaN else { continue }
            for spec in seg.sprites {
                // A fence is drawn as the rail `drawRails` stands along the
                // road, not as a billboard; without the retail art the fallen
                // back post is the only fence there is.
                if spec.kind == .barrier && railTexture != nil { continue }
                let node = obtainEntity(EntityKey(kind: spec.kind, tier: spec.tier))
                let ex = p.screenX + spec.offset * p.screenW
                let ey = fy(p.screenY)
                node.position = CGPoint(x: ex, y: ey)
                // How much of the road the sprite covers. A pit and a sign
                // carry their own width in the track data; everything else is
                // drawn at the width its own model was built at, measured
                // against the nine units the road is across.
                let roadFraction: CGFloat
                switch spec.kind {
                case .hole, .ramp:
                    // A pit and a ramp are as wide as the run of cells they
                    // cover, so the track data carries their width.
                    roadFraction = spec.width > 0 ? spec.width : holeHalfWidth * 2
                case .signBang, .signConstruction, .signStop:
                    let own = SignKind(entity: spec.kind)?.widthFraction ?? 0.42
                    roadFraction = spec.width > 0 ? spec.width : CGFloat(own)
                default:
                    roadFraction = Sprites.entityModelWidth(spec.kind) / roadModelWidth
                }
                // A road fraction is measured against the whole road, and
                // `screenW` is half of it on screen, so it doubles.
                let spriteWidth = roadFraction * p.screenW * 2
                // Every body is built at its `entityBaseWidth`, so this scales
                // the art to the road rather than the road to the art. A
                // turret's tiers come out of their own artwork on top of this:
                // all eight are baked into one canvas, so the wider meshes fill
                // that canvas and reach further across the road on their own.
                let scale = spriteWidth / Sprites.entityBaseWidth(spec.kind)
                node.setScale(max(0.02, scale))
                node.isHidden = false
                node.zPosition = -CGFloat(n) + 0.5
            }
        }
        // Hide unused pooled entities.
        for (key, nodes) in entityPool {
            let used = entityUse[key] ?? 0
            if used < nodes.count {
                for i in used..<nodes.count { nodes[i].isHidden = true }
            }
        }
    }

    private func obtainEntity(_ key: EntityKey) -> SKNode {
        var arr = entityPool[key] ?? []
        let idx = entityUse[key] ?? 0
        if idx < arr.count {
            entityUse[key] = idx + 1
            return arr[idx]
        }
        // A rock's face is drawn for the pool slot it fills. The stream is the
        // scene's seeded one, so the field a course grows is the same field on
        // every run of it.
        let face = Int(truncatingIfNeeded: sceneRandom.next()) & (Sprites.rockFaces - 1)
        let node = Sprites.makeEntity(key.kind, fringe: fringe, tier: key.tier, face: face)
        node.zPosition = 6
        entityLayer.addChild(node)
        arr.append(node)
        entityPool[key] = arr
        entityUse[key] = idx + 1
        return node
    }

    // MARK: - Projection helpers

    private func project(_ p: inout Projection, cameraX: CGFloat, cameraY: CGFloat, cameraZ: CGFloat) {
        p.camera.x = p.world.x - cameraX
        p.camera.y = p.world.y - cameraY
        p.camera.z = p.world.z - cameraZ
        guard p.camera.z > 0.0001 else {
            // Behind the camera: park it off-screen with no width so neither the
            // highway nor a billboard is drawn from it.
            p.scale = 0
            p.screenX = size.width / 2
            p.screenY = -size.height * 8
            p.screenW = 0
            return
        }
        p.scale = cameraDepth / p.camera.z
        p.screenX = size.width / 2 + p.scale * p.camera.x * size.width / 2
        // The principal point sits on `horizonRow`, so anything level with the
        // camera and infinitely far off converges there instead of mid-frame.
        p.screenY = size.height * horizonRow - p.scale * p.camera.y * size.height / 2
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

    /// World z of the next `JetPackOff` piece at or after the snail, wrapped
    /// round the loop track the way `segmentIndex` wraps a z back to the top.
    /// Returns nil when the course has none, leaving the timed fallback.
    private func nextJetpackOffZ() -> CGFloat? {
        guard !segments.isEmpty else { return nil }
        let start = segmentIndex(at: positionZ)
        for offset in 0..<segments.count {
            let idx = (start + offset) % segments.count
            guard segments[idx].jetpackOff else { continue }
            let z = CGFloat(idx) * segmentLength
            return z <= positionZ ? z + CGFloat(segments.count) * segmentLength : z
        }
        return nil
    }

    private func percentRemaining(_ z: CGFloat, _ total: CGFloat) -> CGFloat {
        guard total > 0 else { return 0 }
        return (z.truncatingRemainder(dividingBy: total)) / total
    }

    private func interpolate(_ a: CGFloat, _ b: CGFloat, _ p: CGFloat) -> CGFloat {
        a + (b - a) * p
    }

    // MARK: - Finish

    /// `signOff` names the line the snail leaves on, for a loss whose cause the
    /// caller knows better than the generic `Dying` set — dying to a slug uses
    /// the retail's own `Slugged` set.
    ///
    /// `handedOver` says whether the run ended at the post office, where the
    /// mail on board is handed in. A run that ended early — the postal meter
    /// drained, a plunge off the road — delivers nothing, so its results screen
    /// reports no packages handed over.
    private func finish(won: Bool, signOff: Sound.Voice? = nil, handedOver: Bool = false) {
        guard state.phase == .running else { return }
        // Everything still on board is delivered at the post office, which is
        // what the "Parcel Deliver" gauge measures, and is scored there.
        if handedOver {
            state.delivered = state.parcels
            if state.quota > 0 { state.sheet.parcelDeliver += state.delivered * 500 }
        }
        if won {
            state.sheet.bonus += 1000
            // The completion award the results routine works out at `0x404920`
            // and pays into the run's score right after the gauges are read.
            state.completionBonus = Self.completionBonus(
                mode: mode,
                collect: state.collectFraction,
                deliver: state.deliverFraction
            )
            state.sheet.bonus += state.completionBonus
        }
        state.phase = .finished(won: won)
        // The results screen's own fanfare: a clean clear rings the "PERFECT
        // SCORE!" jingle, anything else the crowd, and a loss its own sting.
        Sound.shared.setPostalAlarm(false)
        // Reaching the post office empties the sack: `placepackage` is the
        // sound of the parcels going down on the counter, under the fanfare.
        if handedOver { Sound.shared.play(.deliver) }
        Sound.shared.play(won ? (state.perfect ? .perfect : .win) : .lose)
        Sound.shared.speak(signOff ?? (won ? .victory : .dying))
        publish()
        onFinish?(won)
    }

    private func publish() {
        // The score pays its extra lives out as it is tallied: the retail award
        // routine checks the thousand-point boundary itself (`0x4402a0`) and
        // rings `ExtraLife` when a spare shell is banked. Every award lands
        // before the frame's publish, so this is where the cheque clears.
        if state.bankMilestones() > 0 { Sound.shared.play(.extraLife) }
        onStateChange?(state)
    }

    // MARK: - Completion award

    /// The bonus the results routine pays for finishing (`0x404920`).
    ///
    /// The arcade campaign's share is the flat 50,000 its own line advertises
    /// (`PERFECT SCORE!>50,000 Bonus Points`, `0x4a11fc`), handed over as soon
    /// as the whole quota is in. Every other mode instead reads the two rank
    /// tables at `0x4a11ac` and `0x4a1194`, stepping 10,000 and 5,000 at a
    /// time through six rungs taken from the two parcel gauges — the routine
    /// divides each gauge reading by twenty (`0x4049a9`) and pins the result
    /// between nought and five (`0x4049ba`–`0x4049de`) — with a full house on
    /// both worth the flat 500,000 (`0x7a120`).
    static func completionBonus(mode: GameMode, collect: Double, deliver: Double) -> Int {
        if mode == .arcade { return 50_000 }
        let collectRank = gaugeRank(collect)
        let deliverRank = gaugeRank(deliver)
        if collectRank == 5 && deliverRank == 5 { return 500_000 }
        let collectTable = [10_000, 20_000, 30_000, 40_000, 50_000, 60_000]
        let deliverTable = [5_000, 10_000, 15_000, 20_000, 25_000, 30_000]
        return collectTable[collectRank] + deliverTable[deliverRank]
    }

    /// One gauge's rung: its reading over twenty, clamped to the tables' six
    /// entries.
    private static func gaugeRank(_ fraction: Double) -> Int {
        let reading = Int((max(0, min(1, fraction)) * 100).rounded())
        return max(0, min(5, reading / 20))
    }
}
