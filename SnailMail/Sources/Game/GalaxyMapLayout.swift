import CoreGraphics

/// The star map's geometry, read straight out of the retail executable.
///
/// The build keeps two float tables and normalises both in one pass before the
/// map is built (`0x4088fb`): every x is scaled by `0.8`, every y by
/// `(y * 0.8 - 240) * 0.93 + 250`. The galaxy table at `0x4a1c4c` holds ten
/// `(x, y)` pairs; the star table at `0x4a1d1c` holds a hundred, and the map
/// walks them in tens — galaxy `g`, star `s` reads entry `10g + 2s`, so the
/// fifty playable stars are every other sample along one long path. Walking
/// them in order from galaxy 0 star 0 through galaxy 9 star 4 gives a
/// continuous route with no leg longer than about 70 units, which is the
/// strongest evidence that the reading is right.
///
/// The numbers live in the original's own 640x512 map space.
enum GalaxyMapLayout {
    static let design = CGSize(width: 640, height: 512)

    /// The ten galaxy portraits' anchors, galaxy 0...9 left to right around the
    /// ring the map draws them on.
    static let galaxyCentres: [CGPoint] = [
        CGPoint(x: 83.2, y: 215.0),
        CGPoint(x: 191.2, y: 137.7),
        CGPoint(x: 332.0, y: 97.5),
        CGPoint(x: 466.4, y: 109.4),
        CGPoint(x: 572.0, y: 183.8),
        CGPoint(x: 562.4, y: 305.1),
        CGPoint(x: 473.6, y: 403.3),
        CGPoint(x: 294.4, y: 415.9),
        CGPoint(x: 220.0, y: 320.7),
        CGPoint(x: 342.4, y: 244.0),
    ]

    /// The five stars each galaxy owns, in level order (`star` 0...4).
    static let stars: [[CGPoint]] = [
        [CGPoint(x: 64.0, y: 258.2), CGPoint(x: 53.6, y: 212.1),
         CGPoint(x: 104.8, y: 215.0), CGPoint(x: 66.4, y: 160.0),
         CGPoint(x: 120.0, y: 192.7)],
        [CGPoint(x: 161.6, y: 158.5), CGPoint(x: 206.4, y: 152.5),
         CGPoint(x: 174.4, y: 119.8), CGPoint(x: 219.2, y: 109.4),
         CGPoint(x: 251.2, y: 141.4)],
        [CGPoint(x: 300.0, y: 119.8), CGPoint(x: 336.8, y: 122.8),
         CGPoint(x: 321.6, y: 74.4), CGPoint(x: 353.6, y: 87.8),
         CGPoint(x: 394.4, y: 85.6)],
        [CGPoint(x: 424.0, y: 124.3), CGPoint(x: 458.4, y: 72.2),
         CGPoint(x: 481.6, y: 123.5), CGPoint(x: 506.4, y: 104.2),
         CGPoint(x: 514.4, y: 143.6)],
        [CGPoint(x: 566.4, y: 158.5), CGPoint(x: 540.8, y: 202.4),
         CGPoint(x: 604.8, y: 165.2), CGPoint(x: 584.8, y: 209.1),
         CGPoint(x: 588.8, y: 239.6)],
        [CGPoint(x: 601.6, y: 285.0), CGPoint(x: 603.2, y: 369.0),
         CGPoint(x: 560.0, y: 279.0), CGPoint(x: 511.2, y: 314.0),
         CGPoint(x: 536.0, y: 372.0)],
        [CGPoint(x: 509.6, y: 377.2), CGPoint(x: 492.8, y: 424.1),
         CGPoint(x: 441.6, y: 401.0), CGPoint(x: 428.8, y: 334.8),
         CGPoint(x: 407.2, y: 418.9)],
        [CGPoint(x: 352.0, y: 421.1), CGPoint(x: 316.8, y: 442.0),
         CGPoint(x: 233.6, y: 425.6), CGPoint(x: 308.8, y: 385.4),
         CGPoint(x: 272.0, y: 386.2)],
        [CGPoint(x: 243.2, y: 342.3), CGPoint(x: 168.0, y: 375.0),
         CGPoint(x: 188.8, y: 325.9), CGPoint(x: 224.8, y: 282.7),
         CGPoint(x: 261.6, y: 311.8)],
        [CGPoint(x: 300.8, y: 256.7), CGPoint(x: 377.6, y: 292.4),
         CGPoint(x: 388.8, y: 248.5), CGPoint(x: 386.4, y: 214.3),
         CGPoint(x: 334.4, y: 189.7)],
    ]

    /// The route the map draws: every star in level order, so galaxy `g` star
    /// `s` is `route[g * 5 + s]`.
    static var route: [CGPoint] { stars.flatMap { $0 } }

    /// The star's map position, so callers never index the tables by hand.
    static func point(galaxy: Int, star: Int) -> CGPoint {
        let g = max(0, min(galaxy, stars.count - 1))
        let s = max(0, min(star, stars[g].count - 1))
        return stars[g][s]
    }

    static func point(galaxy: Int) -> CGPoint {
        let g = max(0, min(galaxy, galaxyCentres.count - 1))
        return galaxyCentres[g]
    }
}
