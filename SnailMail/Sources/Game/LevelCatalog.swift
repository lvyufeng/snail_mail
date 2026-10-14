import Foundation
import simd

/// One star of the original arcade campaign, recovered from the shipped
/// `SnailMail.dat` archive (its 12-byte index entries point straight at the
/// per-level scripts). Every field is the value the 2005 build shipped with,
/// so the remake stops guessing its per-level tuning from the mode alone.
struct ArcadeLevel: Identifiable {
    let id: Int             // 0-based star index, matches the original Arcade%03i.txt
    let galaxy: Int         // 0...9
    let star: Int           // 0...4 within the galaxy
    let name: String        // the level's own title
    let speed: Int          // 0...100
    let salt: Int           // 0...100 salt probability
    let trash: Int          // 0...100 garbage (asteroid/slug) probability
    let slug: Int           // 0...100 slug probability, where the level sets one
    let parcels: Int
    let quota: Int
    let route: Int          // original track length, 200...1000
    let background: String
    let fringe: SIMD3<Double>

    /// The remake lays its road out in fixed-length segments, so the original
    /// "approximate length of track" is scaled to a segment count.
    var segments: Int { max(80, min(900, Int(Double(route) * 0.4))) }
}

/// The campaign layout and the per-level tuning decoded from the original data file.
enum LevelCatalog {
    /// Galaxy names as the original's map screen prints them.
    static let galaxies = [
        "Pomacea cuprina",
        "Ferrissia rivularis",
        "Marisa rotula",
        "Planoribis rubrum",
        "Viviparis malleatus",
        "Melanoides tuberculata",
        "Helisoma",
        "Planorbis corneus",
        "Segmentina victoriae",
        "Pomacea cuprina aurea",
    ]

    static let arcade: [ArcadeLevel] = [
        ArcadeLevel(id: 0, galaxy: 0, star: 0, name: "Test", speed: 40, salt: 10, trash: 0, slug: 65, parcels: 5, quota: 1, route: 500, background: "SpacePurple", fringe: SIMD3(128, 24, 200)),
        ArcadeLevel(id: 1, galaxy: 0, star: 1, name: "Snail Mail 101", speed: 20, salt: 10, trash: 10, slug: 0, parcels: 15, quota: 0, route: 500, background: "SpacePurple", fringe: SIMD3(128, 24, 200)),
        ArcadeLevel(id: 2, galaxy: 0, star: 2, name: "Jump Pod", speed: 20, salt: 10, trash: 10, slug: 0, parcels: 20, quota: 1, route: 500, background: "SpacePurple", fringe: SIMD3(128, 24, 200)),
        ArcadeLevel(id: 3, galaxy: 0, star: 3, name: "Loopy", speed: 20, salt: 10, trash: 0, slug: 10, parcels: 25, quota: 1, route: 500, background: "SpacePurple", fringe: SIMD3(128, 24, 200)),
        ArcadeLevel(id: 4, galaxy: 0, star: 4, name: "Jumper!", speed: 20, salt: 10, trash: 15, slug: 0, parcels: 15, quota: 1, route: 500, background: "SpacePurple", fringe: SIMD3(128, 24, 200)),
        ArcadeLevel(id: 5, galaxy: 1, star: 0, name: "Hills and Valleys", speed: 20, salt: 10, trash: 10, slug: 0, parcels: 20, quota: 0, route: 500, background: "SpacePurple", fringe: SIMD3(128, 24, 200)),
        ArcadeLevel(id: 6, galaxy: 1, star: 1, name: "Keep Still!", speed: 25, salt: 10, trash: 10, slug: 0, parcels: 20, quota: 1, route: 500, background: "SpaceBlue", fringe: SIMD3(128, 24, 200)),
        ArcadeLevel(id: 7, galaxy: 1, star: 2, name: "To Infinity!", speed: 25, salt: 10, trash: 10, slug: 0, parcels: 15, quota: 0, route: 500, background: "SpaceBlue", fringe: SIMD3(128, 24, 200)),
        ArcadeLevel(id: 8, galaxy: 1, star: 3, name: "Zigzag Away!", speed: 25, salt: 10, trash: 10, slug: 0, parcels: 20, quota: 0, route: 500, background: "SpaceBlue", fringe: SIMD3(128, 24, 200)),
        ArcadeLevel(id: 9, galaxy: 1, star: 4, name: "Slugfest!", speed: 25, salt: 10, trash: 10, slug: 0, parcels: 20, quota: 0, route: 500, background: "SpaceBlue", fringe: SIMD3(128, 24, 200)),
        ArcadeLevel(id: 10, galaxy: 2, star: 0, name: "Turrets", speed: 25, salt: 10, trash: 20, slug: 0, parcels: 25, quota: 0, route: 1000, background: "SpaceBlue", fringe: SIMD3(128, 24, 200)),
        ArcadeLevel(id: 11, galaxy: 2, star: 1, name: "30 Gph!", speed: 30, salt: 10, trash: 20, slug: 0, parcels: 45, quota: 25, route: 1000, background: "SpaceRed", fringe: SIMD3(128, 24, 200)),
        ArcadeLevel(id: 12, galaxy: 2, star: 2, name: "Slug Attack!", speed: 30, salt: 10, trash: 30, slug: 0, parcels: 35, quota: 20, route: 200, background: "SpaceRed", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 13, galaxy: 2, star: 3, name: "Loopsville", speed: 30, salt: 10, trash: 30, slug: 0, parcels: 40, quota: 20, route: 500, background: "SpaceRed", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 14, galaxy: 2, star: 4, name: "Jump Junction", speed: 30, salt: 10, trash: 30, slug: 0, parcels: 35, quota: 20, route: 500, background: "SpaceRed", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 15, galaxy: 3, star: 0, name: "Curvature", speed: 30, salt: 10, trash: 30, slug: 0, parcels: 35, quota: 20, route: 500, background: "SpaceRed", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 16, galaxy: 3, star: 1, name: "Flying Slugs", speed: 35, salt: 10, trash: 30, slug: 0, parcels: 30, quota: 10, route: 500, background: "SpacePurple", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 17, galaxy: 3, star: 2, name: "Sodium Chloride", speed: 30, salt: 70, trash: 30, slug: 0, parcels: 35, quota: 10, route: 500, background: "SpacePurple", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 18, galaxy: 3, star: 3, name: "Distorted Route", speed: 35, salt: 20, trash: 30, slug: 0, parcels: 40, quota: 10, route: 500, background: "SpacePurple", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 19, galaxy: 3, star: 4, name: "Slug Half Pipe", speed: 35, salt: 20, trash: 30, slug: 0, parcels: 30, quota: 10, route: 500, background: "SpacePurple", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 20, galaxy: 4, star: 0, name: "40 Gph", speed: 40, salt: 20, trash: 30, slug: 0, parcels: 40, quota: 10, route: 500, background: "SpacePurple", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 21, galaxy: 4, star: 1, name: "Return of the Slugs!", speed: 40, salt: 20, trash: 30, slug: 0, parcels: 40, quota: 0, route: 500, background: "SpaceBlue", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 22, galaxy: 4, star: 2, name: "Twisters", speed: 40, salt: 20, trash: 30, slug: 0, parcels: 30, quota: 10, route: 500, background: "SpaceBlue", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 23, galaxy: 4, star: 3, name: "Sideways Snail", speed: 40, salt: 20, trash: 30, slug: 0, parcels: 30, quota: 10, route: 500, background: "SpaceBlue", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 24, galaxy: 4, star: 4, name: "Zero G", speed: 40, salt: 20, trash: 30, slug: 0, parcels: 30, quota: 10, route: 500, background: "SpaceBlue", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 25, galaxy: 5, star: 0, name: "Under Construction", speed: 45, salt: 20, trash: 30, slug: 0, parcels: 30, quota: 10, route: 500, background: "SpaceBlue", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 26, galaxy: 5, star: 1, name: "Barricades", speed: 45, salt: 20, trash: 30, slug: 0, parcels: 30, quota: 10, route: 500, background: "SpaceRed", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 27, galaxy: 5, star: 2, name: "Tramponus", speed: 45, salt: 20, trash: 30, slug: 0, parcels: 30, quota: 10, route: 500, background: "SpaceRed", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 28, galaxy: 5, star: 3, name: "Twisterific", speed: 45, salt: 20, trash: 30, slug: 0, parcels: 30, quota: 10, route: 500, background: "SpaceRed", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 29, galaxy: 5, star: 4, name: "Slug Invasion!", speed: 45, salt: 20, trash: 30, slug: 0, parcels: 30, quota: 10, route: 500, background: "SpaceRed", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 30, galaxy: 6, star: 0, name: "Danger Ramps!", speed: 50, salt: 20, trash: 30, slug: 0, parcels: 30, quota: 10, route: 500, background: "SpaceRed", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 31, galaxy: 6, star: 1, name: "Skinny route", speed: 50, salt: 20, trash: 30, slug: 0, parcels: 30, quota: 10, route: 500, background: "SpaceBlue", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 32, galaxy: 6, star: 2, name: "Poorly Funded", speed: 55, salt: 20, trash: 60, slug: 0, parcels: 30, quota: 10, route: 500, background: "SpaceBlue", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 33, galaxy: 6, star: 3, name: "Path Bends", speed: 50, salt: 20, trash: 20, slug: 0, parcels: 30, quota: 10, route: 500, background: "SpaceBlue", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 34, galaxy: 6, star: 4, name: "Rocket Snail", speed: 50, salt: 20, trash: 30, slug: 0, parcels: 30, quota: 10, route: 500, background: "SpaceBlue", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 35, galaxy: 7, star: 0, name: "Turret Blockers", speed: 50, salt: 20, trash: 60, slug: 0, parcels: 30, quota: 5, route: 600, background: "SpaceBlue", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 36, galaxy: 7, star: 1, name: "Explosive", speed: 50, salt: 20, trash: 60, slug: 0, parcels: 30, quota: 5, route: 600, background: "SpacePurple", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 37, galaxy: 7, star: 2, name: "Jump Over!", speed: 50, salt: 20, trash: 60, slug: 0, parcels: 30, quota: 5, route: 600, background: "SpacePurple", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 38, galaxy: 7, star: 3, name: "Airborne Snail", speed: 50, salt: 20, trash: 40, slug: 0, parcels: 30, quota: 5, route: 600, background: "SpacePurple", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 39, galaxy: 7, star: 4, name: "Sodium Squared", speed: 50, salt: 100, trash: 20, slug: 0, parcels: 30, quota: 5, route: 600, background: "SpacePurple", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 40, galaxy: 8, star: 0, name: "Asteroids", speed: 55, salt: 20, trash: 100, slug: 0, parcels: 50, quota: 1, route: 500, background: "SpacePurple", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 41, galaxy: 8, star: 1, name: "Corkscrews!", speed: 30, salt: 20, trash: 30, slug: 0, parcels: 30, quota: 10, route: 500, background: "SpacePurple", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 42, galaxy: 8, star: 2, name: "60 Gph!", speed: 60, salt: 20, trash: 60, slug: 0, parcels: 30, quota: 5, route: 600, background: "SpacePurple", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 43, galaxy: 8, star: 3, name: "Air Mail!", speed: 60, salt: 20, trash: 60, slug: 0, parcels: 20, quota: 5, route: 600, background: "SpacePurple", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 44, galaxy: 8, star: 4, name: "Mactabilis", speed: 60, salt: 20, trash: 60, slug: 0, parcels: 30, quota: 5, route: 500, background: "SpacePurple", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 45, galaxy: 9, star: 0, name: "Snail Captain!", speed: 60, salt: 20, trash: 60, slug: 0, parcels: 50, quota: 5, route: 600, background: "SpacePurple", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 46, galaxy: 9, star: 1, name: "70 Gph!", speed: 70, salt: 20, trash: 60, slug: 0, parcels: 45, quota: 5, route: 600, background: "SpaceBlue", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 47, galaxy: 9, star: 2, name: "Tramponus Durus", speed: 70, salt: 30, trash: 60, slug: 0, parcels: 40, quota: 5, route: 600, background: "SpaceBlue", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 48, galaxy: 9, star: 3, name: "80 Gph!", speed: 80, salt: 20, trash: 30, slug: 0, parcels: 40, quota: 5, route: 600, background: "SpaceBlue", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 49, galaxy: 9, star: 4, name: "90 Gph!", speed: 90, salt: 20, trash: 30, slug: 0, parcels: 40, quota: 5, route: 600, background: "SpaceBlue", fringe: SIMD3(222, 255, 10)),
        ArcadeLevel(id: 50, galaxy: 10, star: 0, name: "100 Gph!", speed: 100, salt: 30, trash: 30, slug: 0, parcels: 40, quota: 5, route: 600, background: "SpaceBlue", fringe: SIMD3(222, 255, 10)),
    ]

    /// Real challenge-mode tuning from the shipped `Challenge000.txt`: a random
    /// route, no parcels and the hazards turned up high.
    static let challenge = (speed: 100, salt: 10, trash: 65, parcels: 0,
                            quota: 0, route: 3000, background: "SpaceRed",
                            fringe: SIMD3(0.0, 255.0, 254.0))

    /// Real tutorial tuning from the shipped `Tutorial.txt`.
    static let tutorial = (speed: 10, salt: 0, trash: 0, parcels: 3, quota: 0,
                           route: 700, background: "SpaceRed",
                           fringe: SIMD3(128.0, 255.0, 128.0))
}
