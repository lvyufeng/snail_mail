import SpriteKit
import UIKit

/// The retail build's own artwork.
///
/// `tools/import_art.py` decodes the 2005 installer into
/// `SnailMail/Resources/Retail` — the snail's textures, the galaxy and menu
/// backdrops, the sprites and the audio — and a build phase copies that folder
/// into the app bundle. It is deliberately untracked, so on a checkout that has
/// not run the importer every lookup here returns `nil` and the game falls back
/// to the procedural art it can always draw.
enum RetailAssets {

    /// True when the retail folder made it into the bundle.
    static let installed = url("Art/Baked/snail.png") != nil

    private static var textures: [String: SKTexture] = [:]
    private static var billboards: [String: SKTexture] = [:]
    private static var billboardImages: [String: UIImage] = [:]

    // MARK: - Lookup

    static func url(_ path: String) -> URL? {
        let ns = path as NSString
        let dir = ns.deletingLastPathComponent
        let file = ns.lastPathComponent
        let base = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension
        let sub = dir.isEmpty ? "Retail" : "Retail/" + dir
        return Bundle.main.url(forResource: base, withExtension: ext, subdirectory: sub)
    }

    static func image(_ path: String) -> UIImage? {
        guard let url = url(path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    /// A texture for one retail file, decoded once.
    static func texture(_ path: String) -> SKTexture? {
        if let hit = textures[path] { return hit }
        guard let img = image(path) else { return nil }
        let tex = SKTexture(image: img)
        tex.filteringMode = .linear
        textures[path] = tex
        return tex
    }

    /// A texture cropped to its opaque bounds, so a sprite node sized to a
    /// billboard's width shows the artwork at that width instead of showing the
    /// padding the retail canvas carries around it.
    static func billboard(_ path: String) -> SKTexture? {
        if let hit = billboards[path] { return hit }
        guard let img = image(path) else { return nil }
        let tex = SKTexture(image: trimmed(img))
        tex.filteringMode = .linear
        billboards[path] = tex
        return tex
    }

    /// The same crop `billboard(_:)` applies, handed back as a `UIImage` for the
    /// SwiftUI screens.
    static func billboardImage(_ path: String) -> UIImage? {
        if let hit = billboardImages[path] { return hit }
        guard let img = image(path) else { return nil }
        let cropped = trimmed(img)
        billboardImages[path] = cropped
        return cropped
    }

    // MARK: - Backgrounds

    /// The sky a level's `Background:` script names, e.g. `SpacePurple` ->
    /// `Art/Backgrounds/spacepurple.png`.
    static func background(_ name: String) -> SKTexture? {
        texture("Art/Backgrounds/\(name.lowercased()).png")
    }

    /// The two tones the retail build paints a highway with. A level's `Track:`
    /// script picks one of four surfaces — desert sand, grass, ice and a violet
    /// nebula road — and each is a two-tone lattice. These are the mean colours
    /// of the dark and light halves of `Art/Objects/track0-3.png`, so the flat
    /// fill this renderer can draw matches the tiling it cannot map.
    static func roadColours(track: Int) -> (dark: UIColor, light: UIColor) {
        switch max(0, min(3, track)) {
        case 1:  return (UIColor(hex: "#007D17"), UIColor(hex: "#00B016"))
        case 2:  return (UIColor(hex: "#517CA6"), UIColor(hex: "#6AA7CB"))
        case 3:  return (UIColor(hex: "#7D006C"), UIColor(hex: "#AF00A6"))
        default: return (UIColor(hex: "#C07C30"), UIColor(hex: "#D0AE7B"))
        }
    }

    // MARK: - Road surface

    /// One level's highway tiling, reduced to the handful of tones it is drawn
    /// from. The retail `Art/Objects/track0-3.png` is a 256x256 diamond lattice
    /// — light lines over a base colour — and the renderer cannot lay a texture
    /// across a perspective trapezoid, so the file is read as a 16x16 grid of
    /// cells and each road cell takes the tone of the texture cell it covers.
    struct TrackSurface {
        /// Cells on a side of the texture, e.g. 16 for a 256-pixel file.
        let blocks: Int
        /// Tone index per cell, row-major (`blocks * blocks` entries).
        let tone: [UInt8]
        /// The colour each tone index draws with.
        let palette: [UIColor]

        /// The tone at a texture cell, with the lattice wrapping in both axes.
        func toneIndex(blockX: Int, blockY: Int) -> Int {
            let n = blocks
            let bx = ((blockX % n) + n) % n
            let by = ((blockY % n) + n) % n
            return Int(tone[by * n + bx])
        }
    }

    private static var surfaces: [Int: TrackSurface] = [:]

    /// How many tones a road tiling is reduced to. The lattice is a base colour
    /// with a few lighter steps for its lines, so five clusters keep the steps
    /// apart without turning the blocky noise in the file into extra bands.
    private static let roadTones = 5

    static func trackSurface(_ track: Int) -> TrackSurface? {
        let key = max(0, min(3, track))
        if let hit = surfaces[key] { return hit }
        guard let img = image("Art/Objects/track\(key).png"), let cg = img.cgImage else {
            return nil
        }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return nil }
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &data, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        // One mean colour per texture cell, so the JPEG grain in the file
        // averages out before the tones are picked.
        let blocks = 16
        let bw = max(1, w / blocks), bh = max(1, h / blocks)
        var cells: [(r: Double, g: Double, b: Double)] = []
        cells.reserveCapacity(blocks * blocks)
        for by in 0..<blocks {
            for bx in 0..<blocks {
                var r = 0.0, g = 0.0, b = 0.0, n = 0.0
                for y in (by * bh)..<min((by + 1) * bh, h) {
                    for x in (bx * bw)..<min((bx + 1) * bw, w) {
                        let o = (y * w + x) * 4
                        r += Double(data[o]); g += Double(data[o + 1]); b += Double(data[o + 2])
                        n += 1
                    }
                }
                cells.append((r / n, g / n, b / n))
            }
        }

        // k-means on the cell colours, seeded along the luminance order.
        let k = min(roadTones, cells.count)
        let lum = cells.map { 0.299 * $0.r + 0.587 * $0.g + 0.114 * $0.b }
        let order = (0..<cells.count).sorted { lum[$0] < lum[$1] }
        var centres: [(r: Double, g: Double, b: Double)] = (0..<k).map { i in
            let at = order[(i * (cells.count - 1)) / max(1, k - 1)]
            return cells[at]
        }
        var assign = [Int](repeating: 0, count: cells.count)
        for _ in 0..<12 {
            for (i, c) in cells.enumerated() {
                var best = 0
                var bestD = Double.greatestFiniteMagnitude
                for (j, m) in centres.enumerated() {
                    let dr = c.r - m.r, dg = c.g - m.g, db = c.b - m.b
                    let d = dr * dr + dg * dg + db * db
                    if d < bestD { bestD = d; best = j }
                }
                assign[i] = best
            }
            var sums = [(r: Double, g: Double, b: Double, n: Double)](
                repeating: (0, 0, 0, 0), count: k)
            for (i, c) in cells.enumerated() {
                let j = assign[i]
                sums[j].r += c.r; sums[j].g += c.g; sums[j].b += c.b; sums[j].n += 1
            }
            for j in 0..<k where sums[j].n > 0 {
                centres[j] = (sums[j].r / sums[j].n, sums[j].g / sums[j].n, sums[j].b / sums[j].n)
            }
        }

        let palette = centres.map {
            UIColor(red: CGFloat($0.r / 255), green: CGFloat($0.g / 255),
                    blue: CGFloat($0.b / 255), alpha: 1)
        }
        let surface = TrackSurface(blocks: blocks,
                                   tone: assign.map { UInt8($0) },
                                   palette: palette)
        surfaces[key] = surface
        return surface
    }

    /// The scroll rate a level's `Background:` script gives its backdrop — the
    /// `Distort:` line in the retail `BACKGROUNDS/*.txt`. A higher number means
    /// the sky streams past faster.
    static func backgroundDistort(_ name: String) -> CGFloat {
        switch name {
        case "SpacePurple":   20
        case "SpaceRed":      10
        case "SpaceBlueswhorl": 10
        case "SpaceGreenwarp":  5
        case "Starmap":        2
        case "Splash":       0.3
        default:               0
        }
    }

    /// A full-screen menu backdrop. The retail art ships as two tiles that
    /// stitch side by side into one 640x512 image.
    static func backdrop(_ stem: String) -> SKTexture? {
        let key = "backdrop:\(stem)"
        if let hit = textures[key] { return hit }
        guard let img = stitched(stem) else { return nil }
        let tex = SKTexture(image: img)
        tex.filteringMode = .linear
        textures[key] = tex
        return tex
    }

    /// The two retail tiles for a backdrop joined into one image, or nil when
    /// the art is not in the bundle. SpriteKit wants the texture; SwiftUI wants
    /// the image itself, so this is the shared stitcher.
    static func stitched(_ stem: String) -> UIImage? {
        if let hit = stitchedCache[stem] { return hit }
        guard let a = image("Art/Backgrounds/\(stem)_a.png"),
              let b = image("Art/Backgrounds/\(stem)_b.png") else { return nil }
        let size = CGSize(width: a.size.width + b.size.width,
                          height: max(a.size.height, b.size.height))
        let img = UIGraphicsImageRenderer(size: size).image { _ in
            a.draw(at: .zero)
            b.draw(at: CGPoint(x: a.size.width, y: 0))
        }
        stitchedCache[stem] = img
        return img
    }

    private static var stitchedCache: [String: UIImage] = [:]

    // MARK: - Slicing

    private static var bands: [String: UIImage] = [:]

    /// A horizontal band of a retail sprite — `y` is the first source row and
    /// `height` the number of rows, both in the file's own pixels. The meter
    /// gauges are a fixed end fitting at each end with a flat run between, so
    /// the middle can be stretched to any height without distorting the art.
    static func band(_ path: String, y: Int, height: Int) -> UIImage? {
        let key = "\(path)#\(y)+\(height)"
        if let hit = bands[key] { return hit }
        guard let img = image(path), let cg = img.cgImage else { return nil }
        let rect = CGRect(x: 0, y: y, width: cg.width, height: min(height, cg.height - y))
        guard rect.height > 0, let cut = cg.cropping(to: rect) else { return nil }
        let out = UIImage(cgImage: cut, scale: img.scale, orientation: img.imageOrientation)
        bands[key] = out
        return out
    }

    // MARK: - Audio

    static func audioURL(_ path: String) -> URL? { url(path) }

    // MARK: - Cropping

    private static func trimmed(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return image }
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &data, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            let row = y * w * 4
            for x in 0..<w where data[row + x * 4 + 3] > 8 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return image }
        let rect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        guard let cropped = cg.cropping(to: rect) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }
}
