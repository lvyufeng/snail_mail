import Foundation
import CoreGraphics

// MARK: - Game modes

/// The original modes: 教学 Tutorial, 战役 Postal (its level files are the
/// `Arcade*.txt` campaign), 练习 Practice, 时速 Time Trial, 挑战 Challenge,
/// plus the mobile-only 挑战+ (Pro Challenge).
enum GameMode: String, CaseIterable, Identifiable {
    case arcade
    case tutorial
    case practice
    case speedRun
    case challenge
    case proChallenge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .arcade: "Postal"
        case .tutorial: "Tutorial"
        case .practice: "Practice"
        case .speedRun: "Time Trial"
        case .challenge: "Challenge"
        case .proChallenge: "Pro"
        }
    }

    /// Original Chinese menu label, shown alongside the title.
    var chinese: String {
        switch self {
        case .arcade: "战役"
        case .tutorial: "教学"
        case .practice: "练习"
        case .speedRun: "时速"
        case .challenge: "挑战"
        case .proChallenge: "挑战+"
        }
    }

    var subtitle: String {
        switch self {
        case .arcade: "The original galaxy campaign, star by star"
        case .tutorial: "Learn to steer, fire and deliver"
        case .practice: "Free drive, hazards do no damage"
        case .speedRun: "Finish the route, fastest wins"
        case .challenge: "Endless hazard gauntlet"
        case .proChallenge: "Mobile Pro Challenge: triple the danger"
        }
    }
}

enum GamePhase: Equatable {
    case ready
    case running
    case paused
    case finished(won: Bool)
}

// MARK: - Entities

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
    var fringe: SIMD3<Double>    // RGB 0...255
    var damageEnabled: Bool       // false in Tutorial / Practice
    var guided: Bool              // shows step-by-step Tutorial hints

    static func forMode(_ mode: GameMode, level: Int) -> LevelConfig {
        switch mode {
        case .arcade:
            // The campaign levels come straight from the original data file, so
            // each star plays with its own speed, hazards, parcel count and route.
            let star = LevelCatalog.arcade[max(0, min(level, LevelCatalog.arcade.count - 1))]
            return LevelConfig(
                name: star.name,
                mode: .arcade,
                speed: CGFloat(star.speed),
                salt: CGFloat(star.salt),
                trash: CGFloat(star.trash),
                slug: CGFloat(star.slug),
                parcels: star.parcels,
                quota: star.quota,
                length: star.segments,
                rows: star.route,
                background: star.background,
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
                fringe: t.fringe,
                damageEnabled: false,
                guided: true
            )
        case .practice:
            return LevelConfig(
                name: "Practice",
                mode: .practice,
                speed: 48,
                salt: 22,
                trash: 34,
                slug: 12,
                parcels: 20,
                quota: 12,
                length: 260,
                rows: 0,
                background: "SpaceGreen",
                fringe: SIMD3(128, 235, 140),
                damageEnabled: false,
                guided: false
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
                fringe: c.fringe,
                damageEnabled: true,
                guided: false
            )
        case .proChallenge:
            return LevelConfig(
                name: "Pro Challenge",
                mode: .proChallenge,
                speed: 74,
                salt: 22,
                trash: 70,
                slug: 24,
                parcels: 60,
                quota: 36,
                length: 6000,
                rows: 0,
                background: "SpacePurple",
                fringe: SIMD3(255, 90, 120),
                damageEnabled: true,
                guided: false
            )
        }
    }
}

// MARK: - Live state

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
    var weaponLevel: Int = 1
    var maxWeaponLevel: Int = 3

    /// The three weapons the original climbs through, in order: the starting
    /// blaster, then the laser, then the rocket launcher the ladder tops out on.
    var weaponName: String {
        switch weaponLevel {
        case ..<2: "BLASTER"
        case 2:    "LASER"
        default:   "ROCKET"
        }
    }

    var invincible: Bool = false
    var sheet = ScoreSheet()
    var elapsed: Double = 0
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
        case .arcade:    routeKey = "arcade\(level)"
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
        }
        var slices: [Slice] = []
        slices.reserveCapacity(max(64, config.rows + 32))
        var familyCount: [String: Int] = [:]

        func appendSegment(_ entry: String) {
            let parts = entry.split(separator: "@", maxSplits: 1)
            let name = String(parts[0])
            let angle = parts.count > 1 ? CGFloat(Double(parts[1]) ?? 0) : nil
            guard let raw = TrackData.grid[name] else { return }
            let family = TrackData.path[name] ?? ""
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
            for (n, row) in rows.enumerated() {
                slices.append(Slice(cells: row, family: family,
                                    along: CGFloat(n) / span, step: 1 / span,
                                    flip: flip, angle: angle,
                                    jetpackOff: jetpackOff))
            }
        }

        let budget = max(24, config.rows)
        var rng = SystemRandomNumberGenerator()
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
                    appendSegment(pool[n % pool.count])
                    n += 1
                }
            }
        }
        appendSegment(route[route.count - 1])
        guard slices.count > 6 else { return nil }

        let count = slices.count

        // The plan view: the road's lane centre, carried forward over rows that
        // leave it blank, then smoothed so a one-column step reads as a bend
        // instead of a kink. Rows with no real band of road — the airborne gap
        // in a jump, or a row that holds a lone hazard marker — must not tug
        // the centre sideways, so only a mostly intact row moves it.
        var plan = [CGFloat](repeating: 3.5, count: count)
        var centre: CGFloat = 3.5
        for i in 0..<count {
            let road = slices[i].cells.indices.filter {
                slices[i].cells[$0] != "@" && slices[i].cells[$0] != " "
            }
            if road.count >= 5, let lo = road.first, let hi = road.last {
                centre = (CGFloat(lo) + CGFloat(hi)) / 2
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
            let lo = road.first ?? 0, hi = road.last ?? 7
            let laneCentre = (CGFloat(lo) + CGFloat(hi)) / 2
            let halfLane = max(0.5, (CGFloat(hi) - CGFloat(lo)) / 2)

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

            /// Map a grid column to a position across the road.
            func across(_ col: Int) -> CGFloat {
                max(-0.92, min(0.92, (CGFloat(col) - laneCentre) / (halfLane + 0.5)))
            }
            func spanWidth(_ from: Int, _ to: Int) -> CGFloat {
                min(0.95, (CGFloat(to - from + 1)) / (2 * halfLane + 1))
            }

            var sprites: [EntitySpec] = []
            var saltCount = 0
            // A row wall-to-wall of one fence character is the lip of a ledge
            // the road runs across, not a fence to weave through, so it must
            // stay passable. Only a fence that leaves a gap to thread counts.
            let band = row[lo...hi]
            let fenceChars: Set<Character> = ["|", "=", "-", "{", "}"]
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
                case "0", "1", "2", "3":
                    sprites.append(EntitySpec(kind: ch == "0" ? .turret : .asteroid,
                                              offset: across(col), depth: 0.5))
                case "#":
                    // A pit is as wide as the run of cells it covers, so it can
                    // be steered around exactly like the original's.
                    var end = col
                    while end + 1 < 8 && row[end + 1] == "#" { end += 1 }
                    sprites.append(EntitySpec(kind: .hole,
                                              offset: across((col + end) / 2),
                                              depth: 0.5,
                                              width: spanWidth(col, end)))
                    col = end
                case "+":
                    sprites.append(EntitySpec(kind: .ringUpgrade, offset: 0, depth: 0.5))
                case "~":
                    sprites.append(EntitySpec(kind: .ringSlow, offset: 0, depth: 0.5))
                case ">":
                    sprites.append(EntitySpec(kind: .ringExplode, offset: 0, depth: 0.5))
                case "!":
                    sprites.append(EntitySpec(kind: .ringNormal, offset: 0, depth: 0.5))
                case "o":
                    sprites.append(EntitySpec(kind: .arch, offset: 0, depth: 0.5))
                case "*":
                    sprites.append(EntitySpec(kind: .parcel, offset: 0, depth: 0.5))
                case "$":
                    sprites.append(EntitySpec(kind: .parcel, offset: across(col), depth: 0.5))
                case "|", "=", "-", "{", "}":
                    // Fences, rails and the pillars of a cage: solid pieces the
                    // snail has to thread between. A full-width row is a ledge
                    // lip, so it is left clear.
                    if !solidRow {
                        sprites.append(EntitySpec(kind: .barrier, offset: across(col),
                                                  depth: 0.5))
                    }
                case "<", "R":
                    sprites.append(EntitySpec(kind: .ramp, offset: across(col), depth: 0.5))
                case "(":
                    sprites.append(EntitySpec(kind: .trampoline, offset: across(col),
                                              depth: 0.5))
                case "[":
                    sprites.append(EntitySpec(kind: .enemy, offset: across(col), depth: 0.5))
                case "J":
                    sprites.append(EntitySpec(kind: .jetpack, offset: across(col), depth: 0.5))
                default:
                    break
                }
                col += 1
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

        if let last = segments.last {
            last.sprites.append(EntitySpec(kind: .postOffice, offset: 0, depth: 0.5))
        }
        return segments
    }

    static func build(_ config: LevelConfig) -> [RoadSegment] {
        var segments: [RoadSegment] = []
        var rng = SystemRandomNumberGenerator()

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

    private static func scatterEntities(_ segments: inout [RoadSegment], config: LevelConfig, rng: inout SystemRandomNumberGenerator) {
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
