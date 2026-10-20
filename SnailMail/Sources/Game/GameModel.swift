import Foundation
import CoreGraphics

// MARK: - Game modes

/// The 2005 PC build's four modes: 教学 Tutorial, 战役 Postal Mode (its level
/// files are the `Arcade*.txt` campaign), 时速 Time Trial and 挑战 Challenge
/// Mode — the names the retail build's own mode table prints. The
/// later mobile port's Practice and Pro Challenge are not part of this build,
/// so the remake leaves them out.
enum GameMode: String, CaseIterable, Identifiable {
    case arcade
    case tutorial
    case speedRun
    case challenge

    var id: String { rawValue }

    var title: String {
        // The retail build names its four modes in one table built at
        // 0x417c00-0x417e00: `Help` 0x4a38b4, `Tutorial` 0x4a38e4, `Postal Mode`
        // 0x4a38d8, `Time Trial` 0x4a38cc and `Challenge Mode` 0x4a38bc. The
        // remake's third mode is the retail Time Trial.
        switch self {
        case .arcade: "Postal Mode"
        case .tutorial: "Tutorial"
        case .speedRun: "Time Trial"
        case .challenge: "Challenge Mode"
        }
    }

    /// Original Chinese menu label, shown alongside the title.
    var chinese: String {
        switch self {
        case .arcade: "战役"
        case .tutorial: "教学"
        case .speedRun: "时速"
        case .challenge: "挑战"
        }
    }

    var subtitle: String {
        switch self {
        case .arcade: "The galaxy campaign, star by star"
        case .tutorial: "Learn to steer, fire and deliver"
        case .speedRun: "Finish the route, fastest wins"
        case .challenge: "Endless hazard gauntlet"
        }
    }
}

enum GamePhase: Equatable {
    case ready
    case running
    case paused
    case finished(won: Bool)
}

/// The random stream a course is laid out from.
///
/// Every draw the builder makes — which free slice a hazard lands on, where
/// across the road it sits, how a hill is shaped — comes from one of these, so
/// seeding it fixes a whole level. A race normally seeds itself from the system
/// and no two runs lay out alike; the debug hook `-seed N` pins it instead,
/// which is what makes a screenshot of a course worth comparing with another.
struct CourseRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // Any seed will do; mixing it once here keeps neighbouring seeds from
        // opening with near-identical draws.
        state = seed &* 0x9E37_79B9_7F4A_7C15 &+ 0x2545_F491_4F6C_DD1D
        if state == 0 { state = 0x9E37_79B9_7F4A_7C15 }
    }

    /// One splitmix64 step: cheap, and mixed enough that consecutive seeds lay
    /// out unrelated courses.
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// The stream a fresh scene draws from: `-seed N` when the launch arguments
    /// pin one, and a system draw otherwise.
    static func launched() -> CourseRandom {
        CourseRandom(seed: launchedSeed())
    }

    /// The seed `launched()` opens that stream with. A scene that draws
    /// something more than once — the backdrop is rebuilt on every resize —
    /// keeps this and opens a fresh stream from it, so the second pass lands
    /// exactly where the first one did.
    static func launchedSeed() -> UInt64 {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-seed"), i + 1 < args.count,
           let seed = UInt64(args[i + 1]) {
            return seed
        }
        return UInt64.random(in: .min ... .max)
    }
}

// MARK: - Entities

/// How wide the highway is in the engine's own units — the space every mesh the
/// 2005 build ships and every `3DModel=` offset in its segment files is written
/// in. A prop's own x-extent over this is the share of the road it covers, which
/// is what the renderer sizes the props against so they keep the proportions
/// they were modelled at.
let roadModelWidth: CGFloat = 9

/// Everything that can sit on the highway, mirroring the symbols in the
/// original segment grid files (`s` salt, `M` meteor, `&` slug, `0` turret,
/// `#` hole, plus parcels, hearts and the ring pickups).
enum EntityKind: CaseIterable {
    case parcel        // collect, counts toward quota
    case salt          // burns you, cannot be destroyed
    case asteroid      // shootable, also slows you on contact
    case slug          // moves, knocks you off, shootable
    case heart         // restores the postal meter
    case ringUpgrade   // power-up ring: raises the weapon tier toward rockets
    case ringSlow      // a dark ring that slows you (avoid)
    case ringExplode   // yellow ring that detonates nearby enemies
    case ringNormal    // plain scoring ring on the route
    case arch          // decorative ring, no effect
    case barrier       // fence / wall piece: solid, dents the meter
    case enemy         // the highway "evil", shootable, knocks you aside
    case ramp          // launches the snail clean over a gap
    case trampoline    // a springier launch
    case jetpack       // pickup: brief burst of flight
    case turret        // immobile, cannot be destroyed, steer around
    case hole          // gap in the road; falling costs health
    case postOffice    // the finish line
    case signBang          // roadside warning sign, scenery only
    case signConstruction  // roadside roadworks board, scenery only
    case signStop          // roadside stop sign, scenery only

    var isShootable: Bool {
        switch self {
        case .asteroid, .slug, .enemy: true
        default: false
        }
    }

    var hurtsOnContact: Bool {
        switch self {
        case .salt, .slug, .turret, .hole, .ringSlow, .barrier, .enemy: true
        default: false
        }
    }

}

/// The roadside signs the retail build places with a `3DModel=` tag on a
/// piece row (`TrackData.sign`). It ships three — a warning "bang" panel, a
/// roadworks board and a stop sign — all scenery the snail drives past.
enum SignKind {
    case bang, construction, stop

    /// The `TrackData.Sign.model` a row names, or nil for a model the remake
    /// does not draw.
    init?(model: String) {
        switch model {
        case "signbang": self = .bang
        case "signconstruction": self = .construction
        case "signstop": self = .stop
        default: return nil
        }
    }

    /// The sign the entity kind draws, if any.
    init?(entity: EntityKind) {
        switch entity {
        case .signBang: self = .bang
        case .signConstruction: self = .construction
        case .signStop: self = .stop
        default: return nil
        }
    }

    var entity: EntityKind {
        switch self {
        case .bang: .signBang
        case .construction: .signConstruction
        case .stop: .signStop
        }
    }

    /// The width the retail model gives the board, in the engine's own units.
    /// The remake draws each sign in those units, so this is both how wide the
    /// sprite is drawn and, over the road width, how much of the track it spans.
    var modelWidth: Double {
        switch self {
        case .bang: 7.9406          // two 1.94 panels, either side of the anchor
        case .construction: 12.0    // the wide hoarding, x -6...6
        case .stop: 1.8669          // one small octagon, x -0.93...0.93
        }
    }

    /// `modelWidth` as a fraction of the road, the way `EntitySpec.width`
    /// measures it.
    var widthFraction: Double { modelWidth / Double(roadModelWidth) }

    /// How wide the remake's own drawing of the sign inks, outline included,
    /// measured on screen with `-artprobe`. The drawing is laid out in the
    /// model's units, so the board and its outline reach a little past
    /// `modelWidth`; the renderer scales by `entityModelWidth / ink` and lands
    /// the drawn board on exactly the stretch of road the mesh covered.
    var signInkWidth: CGFloat {
        switch self {
        case .bang: 8.12
        case .construction: 12.40
        case .stop: 2.06
        }
    }
}

// MARK: - World geometry

struct Vec3 {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var z: CGFloat = 0
}

/// A projected point: world position, camera-relative position and the final
/// screen position used to draw.
struct Projection {
    var world = Vec3()
    var camera = Vec3()
    var screenX: CGFloat = 0
    var screenY: CGFloat = 0
    var screenW: CGFloat = 0
    var scale: CGFloat = 0
}

struct EntitySpec {
    let kind: EntityKind
    /// Horizontal placement across the road, -1 (left edge) ... 1 (right edge).
    let offset: CGFloat
    /// Extra depth within the segment, 0...1.
    let depth: CGFloat
    /// How much of the road the entity covers, as a fraction of the full width.
    /// Zero means "use the kind's own footprint" (see `GameScene`).
    var width: CGFloat = 0
    /// Which pillar mesh a turret wears. The build models the post at eight
    /// widths (`X/PILLAR1..8.X2`) but the course grid never spells which one it
    /// wants, so every turret a piece places is the slim first tier and this
    /// only carries the size a debug hook or the procedural art asks for.
    var tier: Int = 1
}

/// One slice of road. The list of these forms the whole course, exactly like
/// the segment files the original shipped with.
final class RoadSegment {
    let index: Int
    var p1 = Projection()
    var p2 = Projection()
    var curve: CGFloat = 0
    var sprites: [EntitySpec] = []
    var banding: Int = 0
    var looped = false
    var clip: CGFloat = 0
    /// Screen-plane roll of the snail while it is on this slice, in radians,
    /// at the near (`roll`) and far (`rollEnd`) end. Non-zero on the families
    /// that fly the snail through a loop or a corkscrew.
    var roll: CGFloat = 0
    var rollEnd: CGFloat = 0
    /// True where the grid leaves the road out altogether. The jump pieces
    /// spell the void they fly over as a run of blank rows, so nothing is
    /// drawn for these slices and the snail arcs across them.
    var airborne = false
    /// The slice index the airborne run starts at, and how many slices long
    /// the whole run is. Both are only meaningful on an `airborne` slice, and
    /// they let the renderer measure how far across the void the snail is.
    var gapStart = 0
    var gapRun = 0
    /// True on the piece that switches a jetpack back off (`JetPackOff.txt`),
    /// which the levels drop in after the gaps the jetpack is meant to clear.
    var jetpackOff = false
    /// Index into `TrackData.tutorialScript` for the pool entry this slice came
    /// from, or -1 where the run has no script — every level but the tutorial.
    var script = -1
    /// True on a row the piece tags `NoFall`: the build's own word for a row a
    /// snail may cross without dropping off the highway. Every one of them
    /// lies under a trampoline's bounce, where the road is left behind and has
    /// to be picked up again on the way down.
    var noFall = false

    init(index: Int) { self.index = index }
}

// MARK: - Level configuration

/// Per-mode tuning for the course: speed, hazard density and length, mirroring
/// the feel of the original's mode files.
struct LevelConfig {
    var name: String
    var mode: GameMode
    var speed: CGFloat            // 0...100
    var salt: CGFloat             // 0...100 probability
    var trash: CGFloat            // 0...100 probability (asteroids/garbage/slugs)
    var slug: CGFloat             // 0...100 slug probability, where the level sets one
    var parcels: Int
    var quota: Int
    var length: Int               // approximate number of segments
    var rows: Int                 // the original `Length:` budget, in track rows
    var background: String
    var track: Int                // the `Track:` number naming the trackN.png/slideN.png pair
    var fringe: SIMD3<Double>    // RGB 0...255
    var damageEnabled: Bool       // false in Tutorial
    var guided: Bool              // shows step-by-step Tutorial hints

    /// `track` pins the `Track:` number a mode would otherwise draw at random,
    /// which is what lets a replay meet the road surface it was recorded on.
    static func forMode(_ mode: GameMode, level: Int, track pinnedTrack: Int? = nil) -> LevelConfig {
        switch mode {
        case .arcade:
            // The campaign levels come straight from the original data file, so
            // each star plays with its own speed, hazards, parcel count and
            // route. The start screen's `Select Speed` / `Select Difficulty`
            // knobs scale the level's own numbers the way the original's did.
            let star = LevelCatalog.star(level)
            let tuning = GameSettings.shared
            return LevelConfig(
                name: star.name,
                mode: .arcade,
                speed: CGFloat(star.speed) * CGFloat(tuning.speedScale),
                salt: min(100, CGFloat(star.salt) * CGFloat(tuning.difficultyScale)),
                trash: min(100, CGFloat(star.trash) * CGFloat(tuning.difficultyScale)),
                slug: CGFloat(star.slug),
                parcels: star.parcels,
                quota: star.quota,
                length: star.segments,
                rows: star.route,
                background: star.background,
                track: star.track,
                fringe: star.fringe,
                damageEnabled: true,
                guided: false
            )
        case .tutorial:
            let t = LevelCatalog.tutorial
            return LevelConfig(
                name: "Tutorial",
                mode: .tutorial,
                speed: CGFloat(t.speed),
                salt: CGFloat(t.salt),
                trash: CGFloat(t.trash),
                slug: 0,
                parcels: t.parcels,
                quota: t.quota,
                length: Int(Double(t.route) * 0.4),
                rows: t.route,
                background: t.background,
                track: 0,
                fringe: t.fringe,
                damageEnabled: false,
                guided: true
            )
        case .speedRun:
            return LevelConfig(
                name: "Speed",
                mode: .speedRun,
                speed: 82,
                salt: 14,
                trash: 26,
                slug: 9,
                parcels: 24,
                quota: 16,
                length: 340,
                rows: 0,
                background: "SpaceRed",
                // Speed Run is the remake's own mode, and the retail build ships
                // no script for it. It plays the highway the campaign opens on —
                // the warm tan road (track 0) — so the mode has one settled look
                // instead of a surface drawn at random per run. Challenge keeps
                // the random draw, which is what `Challenge000.txt` asks for.
                track: pinnedTrack ?? 0,
                fringe: SIMD3(255, 150, 70),
                damageEnabled: true,
                guided: false
            )
        case .challenge:
            let c = LevelCatalog.challenge
            return LevelConfig(
                name: "Challenge",
                mode: .challenge,
                speed: CGFloat(c.speed),
                salt: CGFloat(c.salt),
                trash: CGFloat(c.trash),
                slug: 0,
                parcels: c.parcels,
                quota: c.quota,
                length: Int(Double(c.route) * 0.4),
                rows: c.route,
                background: c.background,
                // The retail challenge script asks for `Track:random`.
                track: pinnedTrack ?? Int.random(in: 0...3),
                fringe: c.fringe,
                damageEnabled: true,
                guided: false
            )
        }
    }
}

// MARK: - Live state

/// One rung of the retail weapon ladder.
///
/// The build keeps the rung in the snail's `0x308` and rebuilds everything
/// else from it in the routine at `0x43a180`: a capability mask in `0x338` and
/// the step in `0x2734` that the fire timer advances by. The mask is read in
/// two places. `0x43a2e0` picks one of the three shot meshes from its low
/// bits, and the two hit routines (`0x444d0b` and `0x445093`) skip their whole
/// damage block while bit `0x80` is set — the invulnerability the ladder's
/// last rungs carry, and the one the tutorial promises ("I will become
/// invincible") to a snail that has climbed far enough.
///
/// The table is the build's own, quirks and all: rung five is sent down the
/// default path and takes the slowest step on the ladder rather than the one
/// its neighbours use, and rungs three to six hand back a blaster or a laser
/// barrel after the rockets of rung two.
struct WeaponTier {
    /// The rung as the build stores it in `0x308`, counting from zero.
    let rung: Int
    /// `0x338`.
    let mask: Int
    /// `0x2734`.
    let step: Double

    /// The rung the pickup ladder tops out on. `0x4456d7` advances while the
    /// rung is below eight and drops an eighth-rung snail back to seven, so
    /// eight is both the ceiling and a rung he can never climb out of.
    static let topRung = 8

    private static let ladder: [(mask: Int, step: Double)] = [
        (0x01, 0.074074),  // 0 — the blaster a run starts with
        (0x02, 0.074074),  // 1 — the laser
        (0x04, 0.074074),  // 2 — the rocket launcher
        (0x08, 0.111111),  // 3 — a blaster barrel again, firing faster
        (0x10, 0.111111),  // 4
        (0x20, 0.066667),  // 5 — the table's own quirk: the default step
        (0x40, 0.133333),  // 6
        (0xc0, 0.133333),  // 7 — the first invulnerable rung
        (0x90, 0.111111),  // 8
    ]

    /// Anything past the table takes the build's default arm (`0x43a268`).
    private static let beyond = (mask: 0x81, step: 0.066667)

    init(rung: Int) {
        self.rung = rung
        let entry = (rung >= 0 && rung < Self.ladder.count) ? Self.ladder[rung] : Self.beyond
        mask = entry.mask
        step = entry.step
    }

    /// The shot mesh, numbered one to three, as `0x43a2e0` chooses it. Each
    /// mesh owns a bit of the mask — blaster `0x1`, laser `0x2`, rocket `0x4` —
    /// and the ladder's own order decides which of them the snail is carrying.
    /// A mask that names none of them (there is none in the table) leaves the
    /// build with nothing to fire, which the ladder here answers with the
    /// blaster rather than a silent gun.
    var shotClass: Int {
        if mask & 0x69 != 0 { return 1 }
        if mask & 0x12 != 0 { return 2 }
        if mask & 0x4 != 0 { return 3 }
        return 1
    }

    /// Bit `0x80` of the mask: the two hit routines test it and step over the
    /// damage they were about to do.
    var invulnerable: Bool { mask & 0x80 != 0 }

    var name: String {
        switch shotClass {
        case 2:   "LASER"
        case 3:   "ROCKET"
        default:  "BLASTER"
        }
    }

    /// Seconds between shots, worked out by running the build's own fire timer.
    ///
    /// `0x43d031` keeps a per-frame accumulator out of `0x2730`: while the fire
    /// button is down it adds the rung's step every frame, and the moment the
    /// total passes one, the accumulator snaps back to zero so the *next* frame
    /// is the one a shot leaves on. Firing sets it a third above the step
    /// (`0x43d130`) rather than at it, which is what paces sustained fire a
    /// little quicker than the bare step would.
    var fireInterval: Double {
        var accumulator = step + 0.3
        var frames = 1                       // the frame the shot leaves on
        while accumulator > 0 {
            accumulator += step
            frames += 1
            if accumulator > 1 { accumulator = 0 }
        }
        return Double(frames) / 60
    }
}

struct RaceState: Equatable {
    var speed: Double = 0                 // current forward speed (units/s)
    var maxSpeed: Double = 1              // reference top speed
    var distance: Double = 0
    var trackLength: Double = 1
    var postalMeter: Double = 100         // health
    var maxMeter: Double = 100
    var parcels: Int = 0                  // parcels picked up this run
    var quota: Int = 0                    // parcels the level asks for
    var delivered: Int = 0                // parcels handed in at the post office
    /// The rung of the weapon ladder, counted from zero the way the build's
    /// `0x308` does: nought is the blaster a run starts with.
    var weaponLevel: Int = 0
    var maxWeaponLevel: Int = WeaponTier.topRung

    /// Spare shells in hand. The retail build hands a fresh run none at all and
    /// pays one out every time the score passes another thousand points: the
    /// award routine at `0x4402a0` checks the boundary on every payout and banks
    /// the extra lives in `0x4340`, capped at nine. A fatal hit therefore ends
    /// the run until the snail has earned its first spare shell.
    var lives: Int = 0
    /// The thousand-point milestone the score has already paid out on, so a
    /// boundary pays once instead of on every frame the total sits above it.
    var paidMilestone: Int = 0

    static let maxLives = 9
    static let milestoneStep = 1000

    /// Everything the current rung decides: the shot the snail fires, how fast
    /// he fires it and whether he is still taking damage at all.
    var weapon: WeaponTier { WeaponTier(rung: weaponLevel) }

    /// The shot the snail is carrying, named the way the HUD prints it.
    var weaponName: String {
        weapon.name
    }

    /// Climbs one rung, the way `0x4456d7` does when the snail runs through a
    /// power-up ring: an eighth-rung snail is dropped back to seven instead of
    /// being left where he is, so a ring he had to steer for always pays out.
    mutating func climbWeapon() {
        if weaponLevel < WeaponTier.topRung {
            weaponLevel += 1
        } else if weaponLevel == WeaponTier.topRung {
            weaponLevel = WeaponTier.topRung - 1
        }
    }

    var invincible: Bool = false
    var sheet = ScoreSheet()
    /// The completion award the results screen prints on its own line. The
    /// retail build computes it in the results routine (`0x404920`, kept in
    /// `0x48(%ebp)`) and adds it into the run's score, so it reaches the board
    /// with everything else.
    var completionBonus: Int = 0
    /// The tutorial line on screen: the script entry of the furthest piece the
    /// snail has reached (`TrackData.tutorialScript`), or empty when the run
    /// has no script.
    var tutorialMessage: String = ""
    var elapsed: Double = 0
    /// Set once the retail build's own fail-safe has ended the run: the shared
    /// run clock passed its limit (`0x43d1c8`, 21 000 frames — about 350
    /// seconds), which the build announces with a `Time's Up` line (`0x445e70`)
    /// and then ends the race on, in every mode. The results page prints the
    /// same line where any other loss prints its own.
    var timedOut: Bool = false
    var phase: GamePhase = .ready

    var score: Int { sheet.total }

    var progress: Double {
        guard trackLength > 0 else { return 0 }
        return max(0, min(1, distance / trackLength))
    }

    var meterFraction: Double {
        guard maxMeter > 0 else { return 0 }
        return max(0, min(1, postalMeter / maxMeter))
    }

    /// The "Parcel Collect" gauge: how much of the quota is on board.
    var collectFraction: Double {
        guard quota > 0 else { return 1 }
        return max(0, min(1, Double(parcels) / Double(quota)))
    }

    /// The "Parcel Deliver" gauge: how much of the quota has been handed over.
    var deliverFraction: Double {
        guard quota > 0 else { return 1 }
        return max(0, min(1, Double(delivered) / Double(quota)))
    }

    var quotaMet: Bool { quota <= 0 || parcels >= quota }

    /// A full quota handed over without losing a sliver of the postal meter.
    var perfect: Bool { quota > 0 && delivered >= quota && postalMeter >= maxMeter }

    /// Banks the extra lives the score has earned since the last check, the way
    /// `0x4402a0` does when the total crosses another thousand. Returns how many
    /// were paid out so the caller can ring `ExtraLife` (sound id `0x2c`, the
    /// table's `sfx2/ExtraLife.ogg`).
    mutating func bankMilestones() -> Int {
        let reached = sheet.total / Self.milestoneStep
        guard reached > paidMilestone else { return 0 }
        let crossings = reached - paidMilestone
        paidMilestone = reached
        let paid = min(crossings, Self.maxLives - lives)
        lives += paid
        return paid
    }

    /// Spends a spare shell on the snail's behalf after a fatal hit. The retail
    /// build asks the same question of `0x4340` at `0x446e25` before it decides
    /// whether the race continues.
    mutating func spendLife() -> Bool {
        guard lives > 0 else { return false }
        lives -= 1
        return true
    }
}

/// The score breakdown the original prints on its results screen: six separate
/// tallies that add up to the level score.
struct ScoreSheet: Equatable {
    var bonus = 0          // pickup and perfect-clear bonuses
    var parcelDeliver = 0  // points for handing the quota in
    var parcelCollect = 0  // points for picking parcels up
    var ring = 0           // points for rings
    var slug = 0           // points for downing slugs
    var garbage = 0        // points for blasting trash

    var total: Int { bonus + parcelDeliver + parcelCollect + ring + slug + garbage }
}

// MARK: - Track building

enum TrackBuilder {

    static let segmentLength: CGFloat = 200

    static let rumbleLength = 3
    static let roadWidth: CGFloat = 1500

    /// Build a course. The campaign levels (and the tutorial and challenge)
    /// play the retail game's own segments, in the order its level files list
    /// them, with every hazard sitting where its grid puts it. The free modes
    /// keep the procedural generator.
    static func build(_ config: LevelConfig, mode: GameMode, level: Int) -> [RoadSegment] {
        let routeKey: String?
        switch mode {
        case .arcade:    routeKey = "arcade\(LevelCatalog.star(level).source)"
        case .tutorial:  routeKey = "tutorial"
        case .challenge: routeKey = "challenge"
        default:         routeKey = nil
        }
        if let key = routeKey, let course = campaign(key, config: config) {
            return course
        }
        return build(config)
    }

    /// The `Path=` families that lift or drop the road. The original names the
    /// vertical shape of a segment here; the grid itself only ever describes
    /// the plan view, so a hill is a `Path=Hill` segment rather than a taller
    /// block of cells. Values are multiples of the segment length.
    private static let lift: [String: CGFloat] = [
        "Hill": 1.6, "Hill4": 1.2, "Hill4C": 1.2, "Hump": 1.5,
        "SuperTramp": 2.4, "HalfPipe": 1.5, "Wibble": 0.7,
        "Valley": -1.6, "Valley4": -1.2, "Valley4C": -1.2,
        "Dip": -1.4, "DodgeDip": -1.0,
    ]

    /// The `Path=` families that swing the road sideways, as (half-cycles,
    /// amplitude in lanes). A `Wibble` is a wiggle, a `Sweep` one long arc, a
    /// `Slalom` a tight alternating weave. Segments that name no path bend
    /// only where their own grid says so.
    private static let weave: [String: (cycles: CGFloat, amp: CGFloat)] = [
        "Sweep": (0.5, 2.6), "Wibble": (2, 1.4), "Snake": (1.5, 2.2),
        "Slalom": (3, 2.0), "SlalomBig": (2, 2.6), "SlalomDouble": (4, 2.0),
        "Turnover": (1, 2.2), "TurnoverDouble": (2, 2.2), "Turnunder": (1, 2.0),
        "TwisterB": (1.5, 2.0), "Twister2A": (2, 2.0), "Twister2B": (1, 2.2),
        "LoopBow": (1, 2.4), "LoopOut": (1, 2.2), "LoopOut3": (1.5, 2.2),
        "Valley4C": (1, 0.8), "Hill4C": (1, 0.8), "Cage2": (2, 1.2),
    ]

    /// The `Path=` families whose grids are almost empty because the whole
    /// manoeuvre lives in the name: a loop, a corkscrew, a worm, an inversion.
    /// Each is a vertical profile of `cycles` arches over the segment whose
    /// height is `amp` segment lengths, raised to `sharp` so a value below one
    /// keeps a rounded crown above steep sides — a loop reads as a near-vertical
    /// climb and drop rather than a lazy hill. The snail rolls through the
    /// families listed in `rollFamilies` (a full turn for a loop or a screw,
    /// a half turn for an inversion) so the manoeuvre is legible on screen.
    private static let vertical: [String: (amp: CGFloat, cycles: CGFloat, sharp: CGFloat)] = [
        "LoopTheLoop": (3.4, 1, 0.55), "LoopTheLoop2": (3.4, 1, 0.55),
        "LoopTheLoopT2": (3.0, 1, 0.6), "LoopTheLoopT3": (3.0, 1, 0.6),
        "LoopTheLoopT4": (2.6, 1, 0.65), "LoopTheLoopW": (3.2, 1, 0.55),
        "LooptheLoop4": (3.8, 1, 0.5), "LoopBow": (2.6, 1, 0.7),
        "LoopOut": (2.8, 1, 0.6), "LoopOut3": (2.8, 1, 0.6),
        "SCREW": (1.7, 1, 0.9), "Worm": (1.0, 3, 1),
        "Invert": (2.6, 1, 0.7),
        "Toad0": (1.9, 1, 0.8), "Toad1": (1.9, 1, 0.8),
        "ToadPair0": (2.2, 1, 0.8), "ToadPair1": (2.2, 1, 0.8),
    ]

    /// The turn a flight family banks through when the level file names no
    /// `Angle=` of its own, in degrees: a full turn for a loop or a screw, a
    /// half turn at the crown of an inversion, nothing for a worm.
    private static func defaultTurn(_ family: String) -> CGFloat {
        switch family {
        case "LoopTheLoop", "LoopTheLoop2", "LoopTheLoopT2", "LoopTheLoopT3",
             "LoopTheLoopT4", "LoopTheLoopW", "LooptheLoop4", "LoopBow",
             "LoopOut", "LoopOut3", "SCREW":
            return 360
        case "Invert":
            return 180
        default:
            return 0
        }
    }

    /// The family a piece's road follows when it names more than one `Path=`.
    /// The first name is the piece's own manoeuvre — `Under Over.txt` tags its
    /// branches `Hump`, `Dump` and `P2`, and the hump is what the piece is
    /// named for — so the first name that has a profile wins. Pieces whose
    /// names are all bare markers (`zigzag.txt` names `P0`/`P1`/`P2`) keep
    /// their first name, which is all the road needs to tell them apart.
    private static func pathFamily(_ name: String) -> String {
        let names = TrackData.path[name] ?? []
        for candidate in names
        where lift[candidate] != nil || weave[candidate] != nil || vertical[candidate] != nil {
            return candidate
        }
        return names.first ?? ""
    }

    /// How far the snail rolls in the screen plane over one of the flight
    /// families. The level's `Angle=` override wins, so the `Worm.txt
    /// Angle=360` of the challenge gauntlet twists the worm a whole turn while
    /// a plain worm stays flat. A whole number of turns is run evenly so the
    /// snail comes out the right way up; a partial or reversing turn eases out
    /// and back, which is what an `Invert` and a banked `Wibble` want.
    private static func roll(_ family: String, _ along: CGFloat, _ angle: CGFloat?) -> CGFloat {
        let degrees = angle ?? defaultTurn(family)
        let total = degrees * .pi / 180
        guard total != 0 else { return 0 }
        let whole = abs(total.truncatingRemainder(dividingBy: 2 * .pi)) < 0.01
        return total * (whole ? along : sin(.pi * along))
    }

    /// Rebuild a campaign course from the retail segment grids.
    ///
    /// A level file lists a pool of segments; with `Random:no` the original
    /// plays them in the order written and cycles back to the top until the
    /// track reaches its approximate `Length:`. Each grid row is one slice of
    /// road, so the road bends exactly where the grid's drivable cells move
    /// across its eight columns, and every symbol lands in its own lane.
    private static func campaign(_ key: String, config: LevelConfig) -> [RoadSegment]? {
        guard let route = TrackData.route[key], route.count >= 2 else { return nil }
        let pool = route.count > 2 ? Array(route[1..<(route.count - 1)]) : []

        // One entry per grid row: the eight lateral cells, the segment's
        // vertical family, and how far along that segment the row sits.
        struct Slice {
            var cells: [Character]
            var family: String
            var along: CGFloat
            var step: CGFloat
            var flip: CGFloat
            /// The level's `Angle=` override for this piece, in degrees.
            var angle: CGFloat?
            /// Whether this piece is a `JetPackOff` switch.
            var jetpackOff: Bool
            /// Index into `TrackData.tutorialScript` for this entry, or -1.
            var script: Int
            /// The roadside signs the piece hangs off this row.
            var signs: [TrackData.Sign] = []
            /// The mid-air parcels the piece tags on this row.
            var parcels: [TrackData.Parcel] = []
            /// The road band this piece's own `P` row declares for this
            /// row, or `nil` for a row that carries no marker.
            var band: TrackData.Band?
            /// Whether this piece tags this row `NoFall`.
            var noFall = false
        }
        var slices: [Slice] = []
        slices.reserveCapacity(max(64, config.rows + 32))
        var familyCount: [String: Int] = [:]

        func appendSegment(_ entry: String, script scriptIndex: Int = -1) {
            let parts = entry.split(separator: "@", maxSplits: 1)
            let name = String(parts[0])
            let angle = parts.count > 1 ? CGFloat(Double(parts[1]) ?? 0) : nil
            guard let raw = TrackData.grid[name] else { return }
            let family = pathFamily(name)
            let jetpackOff = TrackData.jetpackOff.contains(name)
            // A pool that repeats the same bend should bank the other way the
            // second time round, the way the original's signed angles do.
            let seen = familyCount[family, default: 0]
            familyCount[family] = seen + 1
            // A signed `Angle=` also decides which way the piece banks.
            let flip: CGFloat = angle.map { $0 < 0 ? -1 : 1 }
                ?? (seen % 2 == 0 ? 1 : -1)
            let chars = Array(raw)
            var rows: [[Character]] = []
            var i = 0
            while i + 8 <= chars.count {
                let row = Array(chars[i..<(i + 8)])
                // A row walled off end to end is a seam between segments, not road.
                if !row.allSatisfy({ $0 == "@" }) { rows.append(row) }
                i += 8
            }
            let span = CGFloat(max(1, rows.count - 1))
            // `TrackData.sign` numbers its rows the same way the reader does,
            // counting only the rows that lay road (the all-`@` seams dropped
            // above), so the row it names is `rows`' own index.
            var signsByRow: [Int: [TrackData.Sign]] = [:]
            for sign in TrackData.sign[name] ?? [] {
                signsByRow[sign.row, default: []].append(sign)
            }
            // The same for the parcels a piece hangs in mid-air rather than
            // drawing as a `$` cell.
            var parcelsByRow: [Int: [TrackData.Parcel]] = [:]
            for parcel in TrackData.parcel[name] ?? [] {
                parcelsByRow[parcel.row, default: []].append(parcel)
            }
            // The piece's own `P` row, where it has one: the columns the
            // road runs on while the piece's family carries it off the
            // grid. The glyphs on that row are the declaration, not road.
            var bandsByRow: [Int: TrackData.Band] = [:]
            for band in TrackData.band[name] ?? [] {
                bandsByRow[band.row] = band
            }
            // The same numbering again for the rows the piece marks `NoFall`.
            let noFallRows = Set(TrackData.noFall[name] ?? [])
            for (n, row) in rows.enumerated() {
                slices.append(Slice(cells: row, family: family,
                                    along: CGFloat(n) / span, step: 1 / span,
                                    flip: flip, angle: angle,
                                    jetpackOff: jetpackOff, script: scriptIndex,
                                    signs: signsByRow[n] ?? [],
                                    parcels: parcelsByRow[n] ?? [],
                                    band: bandsByRow[n],
                                    noFall: noFallRows.contains(n)))
            }
        }

        let budget = max(24, config.rows)
        var rng = CourseRandom.launched()
        appendSegment(route[0])
        if !pool.isEmpty {
            // Retail's `Length:` scales the speed and the clock, not the slice
            // count; a level always lays its pool down at least once. Cycling
            // until the row budget is met used to cut the tail of the pool —
            // and with it the `JetPackOff` switch that follows `Jetpack`. Run a
            // whole pass first, then keep going only while the road is short.
            let minDraws = pool.count
            if TrackData.random.contains(key) {
                // The challenge gauntlet is `Random:yes` in the retail level
                // file: its pool is drawn as a shuffled deck, reshuffled every
                // time it runs out, so no two runs lay out the same way.
                var deck: [String] = []
                var drawn = 0
                while (drawn < minDraws || slices.count < budget - 8) && drawn < 4000 {
                    if deck.isEmpty { deck = pool.shuffled(using: &rng) }
                    appendSegment(deck.removeFirst())
                    drawn += 1
                }
            } else {
                var n = 0
                while (n < minDraws || slices.count < budget - 8) && n < 4000 {
                    // The tutorial scripts a line per pool entry, so it needs
                    // to know which entry a piece came from. Its pool is long
                    // enough (1140 rows against a 700 budget) to be laid down
                    // exactly once, in order, which is what the script wants.
                    appendSegment(pool[n % pool.count],
                                  script: key == "tutorial" ? n : -1)
                    n += 1
                }
            }
        }
        appendSegment(route[route.count - 1])
        guard slices.count > 6 else { return nil }

        let count = slices.count

        // The columns a slice's road covers, or `nil` where the row lays none.
        // A piece whose family carries the road off the grid declares the band
        // its own `P` row marks — the glyphs there are the declaration, not
        // road, so that row's cells are never read as one. Every other row's
        // band is the run from its first to its last non-`@`, non-blank cell.
        func roadRun(_ s: Slice) -> (lo: Int, hi: Int, count: Int)? {
            if let b = s.band { return (b.start, b.end, b.end - b.start + 1) }
            let road = s.cells.indices.filter {
                s.cells[$0] != "@" && s.cells[$0] != " "
            }
            guard let lo = road.first, let hi = road.last else { return nil }
            return (lo, hi, road.count)
        }

        // The plan view: the road's lane centre, carried forward over rows that
        // leave it blank, then smoothed so a one-column step reads as a bend
        // instead of a kink. Rows with no real band of road — the airborne gap
        // in a jump, or a row that holds a lone hazard marker — must not tug
        // the centre sideways, so only a mostly intact row moves it. A band a
        // piece declares itself is trusted at any width: a slalom's four
        // columns and a hump's three are the whole road there.
        var plan = [CGFloat](repeating: 3.5, count: count)
        var centre: CGFloat = 3.5
        for i in 0..<count {
            if let run = roadRun(slices[i]),
               slices[i].band != nil || run.count >= 5 {
                centre = (CGFloat(run.lo) + CGFloat(run.hi)) / 2
            }
            var value = centre
            if let w = weave[slices[i].family] {
                value -= w.amp * sin(2 * .pi * w.cycles * slices[i].along) * slices[i].flip
            }
            plan[i] = value
        }
        func blur(_ v: [CGFloat], _ radius: Int) -> [CGFloat] {
            var out = v
            for i in v.indices {
                var sum: CGFloat = 0
                var n: CGFloat = 0
                for j in max(0, i - radius)...min(v.count - 1, i + radius) {
                    sum += v[j]; n += 1
                }
                out[i] = sum / n
            }
            return out
        }
        plan = blur(blur(plan, 14), 14)

        // A bend that keeps leaning one way would walk the road off the screen.
        // Taking out the slow drift leaves the bends centred on the view, the
        // way the original's own angles cycle instead of spiralling.
        let driftWindow = 220
        plan = plan.enumerated().map { i, value in
            let lo = max(0, i - driftWindow), hi = min(count, i + driftWindow + 1)
            return value - plan[lo..<hi].reduce(0, +) / CGFloat(hi - lo)
        }

        // The renderer accumulates `curve` twice to sweep the road sideways, so
        // a small heading change near the camera throws the distant road a long
        // way across the screen. Feed it the second difference of the lane the
        // plan draws, scaled down to a gentle bend, and the road stays on the
        // view instead of fanning off to one side (eight lanes span one road
        // width, so one lane of plan is `laneWidth` of world x).
        let laneWidth = roadWidth / 8
        let bend: CGFloat = 0.25
        var curve = [CGFloat](repeating: 0, count: count)
        for i in 0..<count {
            let back2 = plan[max(0, i - 2)], back1 = plan[max(0, i - 1)]
            curve[i] = max(-20, min(20, bend * (plan[i] - 2 * back1 + back2) * laneWidth))
        }

        var segments: [RoadSegment] = []
        segments.reserveCapacity(count)
        var worldY: CGFloat = 0
        for i in 0..<count {
            let seg = RoadSegment(index: i)
            seg.curve = curve[i]
            seg.banding = (i / rumbleLength) % 2

            let row = slices[i].cells
            let road = row.indices.filter { row[$0] != "@" && row[$0] != " " }
            let metrics = roadRun(slices[i])
            let lo = metrics?.lo ?? 0, hi = metrics?.hi ?? 7
            let laneCentre = (CGFloat(lo) + CGFloat(hi)) / 2

            // A blank row means different things in different pieces. Where a
            // piece names no `Path=`, the road really has stopped: `Easy Gap`
            // spells its chasm as a run of empty rows, `Stepping Stones` its
            // floating slabs, `Forest` the leap over the canopy. Where a piece
            // does name a path, the blank rows are the road itself — a hill
            // lifts it, a slalom swings it out of the grid's eight columns, a
            // worm stands it on its tail — and the `P` markers say so. Only
            // the first kind is a void, and marking it here lets the renderer
            // leave it out and the snail arc across it.
            let airborne = slices[i].family.isEmpty
                && row.allSatisfy { $0 == " " || $0 == "@" || $0 == "M" }
            seg.airborne = airborne
            seg.jetpackOff = slices[i].jetpackOff
            seg.script = slices[i].script
            seg.noFall = slices[i].noFall

            /// Map a grid column to a position across the road.
            func across(_ col: Int) -> CGFloat {
                across(CGFloat(col))
            }
            /// The same for a column that falls between two cells, so a run
            /// of an even number of cells still centres on the road.
            ///
            /// A column is one model unit — `X/PILLAR1.X2` is 1.040 across,
            /// one cell, and the eight drivable columns of `X/PILLAR8.X2`
            /// measure 7.998 — and the ribbon between the tire lines is nine,
            /// so the distance across is `roadModelWidth / 2`. Dividing by the
            /// run's own width instead, as this once did, spread the eight
            /// columns of a full row wall to wall and pushed a three-column
            /// piece's props a third of a unit clear off its road.
            func across(_ col: CGFloat) -> CGFloat {
                max(-0.95, min(0.95, (col - laneCentre) / (roadModelWidth / 2)))
            }
            func spanWidth(_ from: Int, _ to: Int) -> CGFloat {
                min(0.95, (CGFloat(to - from + 1)) / roadModelWidth)
            }

            var sprites: [EntitySpec] = []
            var saltCount = 0
            // A row wall-to-wall of one fence character is the lip of a ledge
            // the road runs across, not a fence to weave through, so it must
            // stay passable. Only a fence that leaves a gap to thread counts.
            let band = row[lo...hi]
            let fenceChars: Set<Character> = ["|", "=", "-"]
            // The ramp markers: a run of these cells is the road itself
            // turning into a ramp, not a prop standing on it.
            let rampChars: Set<Character> = ["<", ">", "{", "}"]
            let solidRow = band.allSatisfy { fenceChars.contains($0) }
            var col = 0
            while col < 8 {
                let ch = row[col]
                switch ch {
                case "s":
                    if saltCount < 6 {
                        sprites.append(EntitySpec(kind: .salt, offset: across(col), depth: 0.5))
                        saltCount += 1
                    }
                case "M":
                    sprites.append(EntitySpec(kind: .asteroid, offset: across(col), depth: 0.5))
                case "&":
                    sprites.append(EntitySpec(kind: .slug, offset: across(col), depth: 0.5))
                case "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
                    // Every digit spells the same block. The build's grid
                    // dispatcher sends `0` down one path and `1`...`9` down
                    // another, but both write the same row kind and the same
                    // mesh, and the value of the digit is never read — so a
                    // piece cannot ask for a wider post by naming a bigger
                    // number. No course ever puts two digits side by side
                    // either, so a digit is always one cell wide, which is the
                    // `X/PILLAR1.X2` slab the grid's own cell measures.
                    sprites.append(EntitySpec(kind: .turret, offset: across(col),
                                              depth: 0.5))
                case "#":
                    // `#` is the grid's other void glyph: the build's own
                    // dispatcher (`0x43672d`) stores a space over the cell, so
                    // the engine reads it as open air exactly like ` `. The voids
                    // that leave road beside them are the pits to weave around —
                    // `Dodge Dip`'s `   ##   ` is the hole it is named for — and
                    // one is as wide as the run of cells it covers.
                    //
                    // A run that closes the whole row is the retail's open void,
                    // though. Every course that writes one hangs it off a
                    // `Path=` that carries the road over it — `Hill`, `Valley`,
                    // `Wibble`, `HalfPipe`, the spawn's own `Start.txt` — so it
                    // is the air under the crest, not a pit. Reading it as a pit
                    // walls the road off with no lane to steer around, and since
                    // the fall rewinds the snail into the same row it becomes an
                    // inescapable loop: the tutorial never gets past its first
                    // piece. Such a run is left as the void it is.
                    var end = col
                    while end + 1 < 8 && row[end + 1] == "#" { end += 1 }
                    if !(col == 0 && end == 7) {
                        sprites.append(EntitySpec(kind: .hole,
                                                  offset: across((col + end) / 2),
                                                  depth: 0.5,
                                                  width: spanWidth(col, end)))
                    }
                    col = end
                case "+":
                    sprites.append(EntitySpec(kind: .ringUpgrade, offset: 0, depth: 0.5))
                case "~":
                    sprites.append(EntitySpec(kind: .ringSlow, offset: 0, depth: 0.5))
                case "^":
                    // The blast ring. `tools/import_tracks.py` folds a
                    // `Ring=Explode` row's glyphs to `^` because the glyph it
                    // stands on (`>`) is a road ramp of its own.
                    sprites.append(EntitySpec(kind: .ringExplode, offset: 0, depth: 0.5))
                case "!":
                    sprites.append(EntitySpec(kind: .ringNormal, offset: 0, depth: 0.5))
                case "o":
                    sprites.append(EntitySpec(kind: .arch, offset: 0, depth: 0.5))
                case "*":
                    sprites.append(EntitySpec(kind: .parcel, offset: 0, depth: 0.5))
                case "$":
                    sprites.append(EntitySpec(kind: .parcel, offset: across(col), depth: 0.5))
                case "|", "=", "-":
                    // Fences, rails and the pillars of a cage: solid pieces the
                    // snail has to thread between. A full-width row is a ledge
                    // lip, so it is left clear.
                    if !solidRow {
                        sprites.append(EntitySpec(kind: .barrier, offset: across(col),
                                                  depth: 0.5))
                    }
                case "<", ">", "{", "}":
                    // The road's own ramp markers. A piece spells its launch
                    // with a run of them across the whole grid — `{>>>>>>}`
                    // throws the snail over the gap ahead, and the run of
                    // `<` on the far side is the bank it comes down on. The
                    // cells are road, not props: the retail build feeds the
                    // four kinds to its road auto-tiler (`0x434bc0` picks a
                    // road piece from `>`=1, `}`=2, `[`=3, `<`=4), and its
                    // own "is there ground here" test (`0x434b60`) answers yes
                    // for every one of them. So the run is drawn as a single
                    // ramp spanning the columns it covers, the width the
                    // launch covers, rather than as one post per column.
                    var end = col
                    while end + 1 < 8 && rampChars.contains(row[end + 1]) { end += 1 }
                    sprites.append(EntitySpec(kind: .ramp,
                                              offset: across((CGFloat(col) + CGFloat(end)) / 2),
                                              depth: 0.5,
                                              width: spanWidth(col, end)))
                    col = end
                case "R":
                    sprites.append(EntitySpec(kind: .ramp, offset: across(col), depth: 0.5))
                case "(":
                    // The trampoline's own mesh spans three cells —
                    // `X/TRAMP.X2` measures 3.000 — and every `(((` a course
                    // ships is exactly that run of three, so the piece is one
                    // pad across the run rather than three pads stacked on one
                    // another.
                    var end = col
                    while end + 1 < 8 && row[end + 1] == "(" { end += 1 }
                    sprites.append(EntitySpec(kind: .trampoline,
                                              offset: across((CGFloat(col) + CGFloat(end)) / 2),
                                              depth: 0.5,
                                              width: spanWidth(col, end)))
                    col = end
                case "[":
                    sprites.append(EntitySpec(kind: .enemy, offset: across(col), depth: 0.5))
                case "J":
                    sprites.append(EntitySpec(kind: .jetpack, offset: across(col), depth: 0.5))
                default:
                    break
                }
                col += 1
            }
            // The piece's roadside signs sit on the row they were tagged
            // with, off to the side the model's own x places them (the
            // engine's road is 9 wide there, so `x / 4.5` is across-road).
            for sign in slices[i].signs {
                guard let kind = SignKind(model: sign.model) else { continue }
                sprites.append(EntitySpec(kind: kind.entity,
                                          offset: max(-0.95, min(0.95, CGFloat(sign.x) / 4.5)),
                                          depth: 0.5,
                                          width: CGFloat(kind.widthFraction)))
            }
            // The parcels a piece hangs in mid-air. They keep the row they
            // were tagged on, which is the row the retail build builds their
            // offset from, so a loop's trail of five climbs the loop rather
            // than lying along its foot.
            for parcel in slices[i].parcels {
                sprites.append(EntitySpec(kind: .parcel,
                                          offset: max(-0.95, min(0.95, CGFloat(parcel.x) / 4.5)),
                                          depth: 0.5))
            }
            seg.sprites = sprites

            // Elevation: the segment's family lifts or drops the road, and a
            // stretch of rough road rides a little higher than the smooth road
            // either side of it. The flight families take their height from
            // `vertical` instead, so a loop or a worm actually leaves the ground.
            let family = slices[i].family
            var y: CGFloat = 0
            if let v = vertical[family] {
                let phase = .pi * v.cycles * slices[i].along
                y = v.amp * pow(abs(sin(phase)), v.sharp) * segmentLength
            } else {
                y = (lift[family] ?? 0) * sin(slices[i].along * .pi) * segmentLength
            }
            if road.count >= 6, road.filter({ row[$0] == "_" }).count >= road.count * 7 / 10 {
                y += 0.25 * segmentLength
            }

            // Roll the snail through the loop, screw and inversion pieces. Each
            // slice records the angle at its near and far end so the renderer can
            // interpolate it with the same fraction it uses for the road height.
            let nextAlong = min(1, slices[i].along + slices[i].step)
            seg.roll = TrackBuilder.roll(family, slices[i].along, slices[i].angle)
            seg.rollEnd = TrackBuilder.roll(family, nextAlong, slices[i].angle)

            seg.p1.world = Vec3(x: 0, y: worldY, z: CGFloat(i) * segmentLength)
            worldY = y
            seg.p2.world = Vec3(x: 0, y: worldY, z: CGFloat(i + 1) * segmentLength)
            segments.append(seg)
        }

        // Label each airborne run with its start and its whole length, so a
        // slice the snail is already halfway across still measures its arc
        // from the near lip of the void. A one- or two-row break in the road
        // would blink a single frame of background past and is not worth
        // flying, so only a run this long or longer becomes a void; the rest
        // are left as ordinary road.
        let minGapRows = 3
        var runStart = -1
        func closeRun(_ end: Int) {
            guard runStart >= 0 else { return }
            let run = end - runStart
            for j in runStart..<end {
                if run >= minGapRows {
                    segments[j].gapStart = runStart
                    segments[j].gapRun = run
                } else {
                    segments[j].airborne = false
                }
            }
            runStart = -1
        }
        for i in 0..<segments.count {
            if segments[i].airborne {
                if runStart < 0 { runStart = i }
            } else {
                closeRun(i)
            }
        }
        closeRun(segments.count)

        // The level files ask for a parcel quota and a weapon ladder, but a
        // route only carries parcel and pickup cells on the segments that name
        // them. Fill in what the grids leave out so the quota is reachable and
        // the blaster can still climb to the rockets.
        func topUp(_ kind: EntityKind, to target: Int, minGap: Int) {
            var needed = target - segments.reduce(0) {
                $0 + $1.sprites.filter { $0.kind == kind }.count
            }
            guard needed > 0 else { return }
            let lo = min(12, segments.count / 4)
            let hi = max(lo + 1, segments.count - 8)
            guard hi > lo else { return }
            var order = Array(lo..<hi)
            order.shuffle(using: &rng)
            var chosen: [Int] = []
            for index in order {
                guard needed > 0 else { break }
                guard segments[index].sprites.isEmpty,
                      !segments[index].airborne,
                      chosen.allSatisfy({ abs($0 - index) >= minGap }) else { continue }
                segments[index].sprites.append(EntitySpec(kind: kind, offset: 0, depth: 0.5))
                chosen.append(index)
                needed -= 1
            }
        }
        topUp(.parcel, to: max(6, max(config.parcels, config.quota + 4)), minGap: 5)
        topUp(.ringUpgrade, to: 4, minGap: 60)
        topUp(.heart, to: max(2, segments.count / 120), minGap: 40)
        scatterHazards(&segments, config: config, rng: &rng)

        if let last = segments.last {
            last.sprites.append(EntitySpec(kind: .postOffice, offset: 0, depth: 0.5))
        }
        return segments
    }

    /// Sprinkle the level's own hazard rates over a course.
    ///
    /// The retail level file sets `Salt:`, `Slug:` and the garbage rate as
    /// 0-100 percentages, and the salt and slug managers spawn against them, so
    /// a level like "Sodium Chloride" (`Salt:70`) is genuinely drowned in salt
    /// and "Sodium Squared" (`Salt:100`) worse still, while the tutorial
    /// (`Salt:0`, `Trash:0`) stays clean. The segment grids only carry the
    /// fixed pieces the piece author placed, so a course laid straight from
    /// them has to add this layer itself.
    private static func scatterHazards(_ segments: inout [RoadSegment],
                                       config: LevelConfig,
                                       rng: inout CourseRandom) {
        guard !config.guided, segments.count > 60 else { return }

        // Fill only the slices the grids left empty, so a scattered hazard
        // never lands on top of a piece's own obstacle or pickup.
        func place(_ kind: EntityKind, count: Int, minGap: Int,
                   offset: ClosedRange<CGFloat> = -0.8...0.8) {
            guard count > 0 else { return }
            var candidates = Array(12..<(segments.count - 6))
            candidates.shuffle(using: &rng)
            var chosen: [Int] = []
            for index in candidates {
                if chosen.count >= count { break }
                guard segments[index].sprites.isEmpty,
                      !segments[index].airborne,
                      chosen.allSatisfy({ abs($0 - index) >= minGap }) else { continue }
                segments[index].sprites.append(EntitySpec(
                    kind: kind,
                    offset: CGFloat.random(in: offset, using: &rng),
                    depth: CGFloat.random(in: 0...1, using: &rng)))
                chosen.append(index)
            }
        }

        let hazardCount = segments.count / 6
        place(.salt, count: Int(CGFloat(hazardCount) * config.salt / 100), minGap: 10)
        place(.asteroid, count: Int(CGFloat(hazardCount) * config.trash / 200), minGap: 8)
        // Levels that name their own slug probability use it; the rest fall back
        // to a share of the garbage rate.
        let slugRate = config.slug > 0 ? config.slug : config.trash / 3
        place(.slug, count: Int(CGFloat(hazardCount) * slugRate / 100), minGap: 12)
        place(.turret, count: segments.count / 130, minGap: 60)
        // A pit is drawn across the middle of the road, so it has to sit there
        // logically too: a random offset would put the pit the player sees and
        // the pit they fall into in different places.
        place(.hole, count: segments.count / 150, minGap: 60, offset: -0.1...0.1)
    }

    static func build(_ config: LevelConfig) -> [RoadSegment] {
        var segments: [RoadSegment] = []
        var rng = CourseRandom.launched()

        func lastY() -> CGFloat { segments.last?.p2.world.y ?? 0 }

        func addSegment(curve: CGFloat, y: CGFloat) {
            let n = segments.count
            let seg = RoadSegment(index: n)
            seg.curve = curve
            seg.banding = (n / rumbleLength) % 2
            seg.p1.world = Vec3(x: 0, y: lastY(), z: CGFloat(n) * segmentLength)
            seg.p2.world = Vec3(x: 0, y: y, z: CGFloat(n + 1) * segmentLength)
            segments.append(seg)
        }

        func addRoad(enter: Int, hold: Int, leave: Int, curve: CGFloat, y: CGFloat) {
            let startY = lastY()
            let endY = startY + y * segmentLength
            let total = enter + hold + leave
            guard total > 0 else { return }
            for n in 0..<enter {
                addSegment(curve: easeIn(0, curve, CGFloat(n) / CGFloat(enter)), y: easeInOut(startY, endY, CGFloat(n) / CGFloat(total)))
            }
            for n in 0..<hold {
                addSegment(curve: curve, y: easeInOut(startY, endY, CGFloat(enter + n) / CGFloat(total)))
            }
            for n in 0..<leave {
                addSegment(curve: easeInOut(curve, 0, CGFloat(n) / CGFloat(leave)), y: easeInOut(startY, endY, CGFloat(enter + hold + n) / CGFloat(total)))
            }
        }

        // Opening straight.
        addRoad(enter: 0, hold: 40, leave: 0, curve: 0, y: 0)

        // Lay out the course in chunks. Curves/hills are chosen so no two
        // adjacent chunks repeat, which keeps the drive readable.
        let chunk = max(18, config.length / 12)
        var remaining = config.length
        var lastCurve: CGFloat = 0
        var hill: CGFloat = 0

        while remaining > 0 {
            let hold = min(chunk, remaining)
            remaining -= hold
            let dir: CGFloat = Bool.random(using: &rng) ? 1 : -1
            var curve = dir * CGFloat.random(in: 1...4, using: &rng)
            if abs(curve - lastCurve) < 1 { curve = -lastCurve }
            hill = CGFloat.random(in: -0.6...0.9, using: &rng)
            let enter = Int.random(in: 8...14, using: &rng)
            let leave = Int.random(in: 8...14, using: &rng)
            addRoad(enter: enter, hold: hold, leave: leave, curve: curve, y: hill)
            lastCurve = curve
        }

        // Closing straight then finish.
        addRoad(enter: 8, hold: 30, leave: 0, curve: 0, y: 0)

        // Scatter entities across the middle of the course.
        scatterEntities(&segments, config: config, rng: &rng)

        // Post office finish at the very last segment.
        if let last = segments.last {
            last.sprites.append(EntitySpec(kind: .postOffice, offset: 0, depth: 0.5))
        }

        return segments
    }

    private static func scatterEntities(_ segments: inout [RoadSegment], config: LevelConfig, rng: inout CourseRandom) {
        guard segments.count > 60 else { return }
        let usable = Array(segments[20..<(segments.count - 30)])

        // Walk the course in a randomised order and greedily drop each pickup on
        // the first free slot that keeps `minGap` segments between neighbours of
        // the same kind. Shuffling first spreads items over the whole route
        // instead of drifting toward one end.
        @discardableResult
        func place(_ kind: EntityKind, count: Int, minGap: Int,
                   avoiding blocked: Set<Int> = [],
                   offset: ClosedRange<CGFloat>? = nil) -> [Int] {
            guard count > 0 else { return [] }
            var candidates = Array(20..<(segments.count - 30))
            candidates.shuffle(using: &rng)
            var chosen: [Int] = []
            for index in candidates {
                if chosen.count >= count { break }
                if blocked.contains(index) { continue }
                if chosen.allSatisfy({ abs($0 - index) >= minGap }) {
                    let seg = segments[index]
                    let range = offset ?? -0.8...0.8
                    seg.sprites.append(EntitySpec(kind: kind,
                                                  offset: CGFloat.random(in: range, using: &rng),
                                                  depth: CGFloat.random(in: 0...1, using: &rng)))
                    chosen.append(index)
                }
            }
            return chosen
        }

        // Weapon upgrades are pickups, not gates. Power-up rings lie in the
        // middle of the road at set points along the route: steer through one and
        // the blaster climbs to the laser and then the rocket launcher. Two
        // chances per rung mean a ring missed while dodging a hazard does not
        // strand the run on the first tier.
        var ringSegments = Set<Int>()
        let lo = 20
        let hi = segments.count - 30
        let span = hi - lo
        if span > 120 {
            for fraction in [0.26, 0.40, 0.64, 0.80] as [CGFloat] {
                var index = lo + Int(CGFloat(span) * fraction)
                while ringSegments.contains(index) && index < hi - 2 { index += 2 }
                guard index < hi - 2 else { continue }
                segments[index].sprites.append(
                    EntitySpec(kind: .ringUpgrade, offset: 0, depth: 0.5))
                ringSegments.insert(index)
            }
        }

        place(.parcel, count: max(1, config.parcels), minGap: 6, avoiding: ringSegments)

        let hazardCount = usable.count / 6
        // Rings are wide and span the whole road, so reserve their segments
        // first. Hazards are then kept off those segments so a meteor or slug
        // never spawns inside a boost ring.
        ringSegments.formUnion(place(.ringExplode, count: max(1, usable.count / 120), minGap: 50, avoiding: ringSegments))
        ringSegments.formUnion(place(.ringSlow, count: max(1, usable.count / 110), minGap: 50, avoiding: ringSegments))

        // The guided tutorial stays clean: pickups and rings only, so a new
        // player can learn the controls without dodging anything.
        if !config.guided {
            place(.salt, count: Int(CGFloat(hazardCount) * config.salt / 100), minGap: 10, avoiding: ringSegments)
            place(.asteroid, count: Int(CGFloat(hazardCount) * config.trash / 200), minGap: 8, avoiding: ringSegments)
            // Levels that name their own slug probability use it; the rest fall
            // back to a share of the garbage rate, as before.
            let slugRate = config.slug > 0 ? config.slug : config.trash / 3
            place(.slug, count: Int(CGFloat(hazardCount) * slugRate / 100), minGap: 12, avoiding: ringSegments)
            place(.turret, count: usable.count / 130, minGap: 60, avoiding: ringSegments)
            // Holes are drawn across the middle of the road, so they must sit
            // there logically too: a random offset would put the pit the player
            // sees and the pit they fall into in different places.
            place(.hole, count: usable.count / 150, minGap: 60,
                  avoiding: ringSegments, offset: -0.1...0.1)
        }
        place(.heart, count: max(1, usable.count / 90), minGap: 40, avoiding: ringSegments)
    }

    // MARK: easing

    static func easeIn(_ a: CGFloat, _ b: CGFloat, _ p: CGFloat) -> CGFloat {
        a + (b - a) * pow(p, 2)
    }
    static func easeInOut(_ a: CGFloat, _ b: CGFloat, _ p: CGFloat) -> CGFloat {
        a + (b - a) * (-cos(p * .pi) / 2 + 0.5)
    }
}
