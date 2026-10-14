import Foundation
import CoreGraphics

// MARK: - Game modes

/// The original modes: 教学 Tutorial, 练习 Practice, 时速 Speed, 挑战
/// Challenge, plus the mobile-only 挑战+ (Pro Challenge).
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
        case .arcade: "Arcade"
        case .tutorial: "Tutorial"
        case .practice: "Practice"
        case .speedRun: "Speed"
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
    case turret        // immobile, cannot be destroyed, steer around
    case hole          // gap in the road; falling costs health
    case postOffice    // the finish line

    var isShootable: Bool {
        switch self {
        case .asteroid, .slug: true
        default: false
        }
    }

    var hurtsOnContact: Bool {
        switch self {
        case .salt, .slug, .turret, .hole, .ringSlow: true
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
