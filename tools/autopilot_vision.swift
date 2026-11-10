#!/usr/bin/env swift
// Read bitmap frames as a road and a snail's horizontal position.
// It does not know GameScene's track state: comparing this output with
// -autopilot-trace shows whether the picture and engine agree.
//
// Usage: swift tools/autopilot_vision.swift OUTPUT FRAME...
import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count >= 3 else {
    fputs("usage: autopilot_vision.swift OUTPUT FRAME...\n", stderr)
    exit(2)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
var lines: [String] = []

struct Picture {
    let width: Int, height: Int, pixels: [UInt8]
    func rgb(_ x: Int, _ y: Int) -> (Double, Double, Double) {
        guard x >= 0, y >= 0, x < width, y < height else { return (0, 0, 0) }
        let at = (y * width + x) * 4
        return (Double(pixels[at]), Double(pixels[at + 1]), Double(pixels[at + 2]))
    }
}

func resized(_ path: String, width: Int = 240, height: Int = 426) -> Picture? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let ok = pixels.withUnsafeMutableBytes { bytes -> Bool in
        guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    return ok ? Picture(width: width, height: height, pixels: pixels) : nil
}

func read(_ path: String) -> [String: Any]? {
    let width = 240
    let height = 426
    guard let small = resized(path, width: width, height: height) else { return nil }
    let tracked = findSnail(small)
    // Track boundaries come from the road rows, calibrated to the screen
    // coordinates the race uses for Turbo's depth.
    let screenY = 1280.0 / 2778.0
    let roadFraction = 1.9447 * screenY - 0.2709
    var bands: [[String: Int]] = []
    let bandY = Int(Double(height) * 0.62)
    if let road = roadCentre(small) {
        let scaled = (road - 0.5) * 2 * 240
        let left = Int(120 + scaled - roadFraction * 120)
        let right = Int(120 + scaled + roadFraction * 120)
        bands.append(["y": bandY, "left": left, "right": right])
    }
    var result: [String: Any] = [
        "frame": URL(fileURLWithPath: path).lastPathComponent,
        "screen_frame": URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
        "width": 240, "height": 426,
        "bands": bands,
        "road": roadBand(small) as Any,
        "roadEdge": roadEdge(small) as Any,
        "roadSpan": roadSpan(small) as Any,
        "trackDetected": !bands.isEmpty,
    ]
    if let road = roadCentre(small) { result["roadCentre"] = road }
    if let tracked { result["snail"] = tracked }
    return result
}

/// Locate the largest continuous, blue road band at a row near Turbo's feet.
/// This is a viewport measurement (0...1), before converting a road fraction
/// into model offset with the engine's own same-frame half-width.
func roadBand(_ bitmap: Picture) -> [String: Any]? {
    let width = bitmap.width, height = bitmap.height
    for fraction in [0.77, 0.74, 0.70, 0.80, 0.66, 0.82, 0.60] {
        let y = Int(Double(height) * fraction)
        var runs: [[Int]] = []
        var run: [Int] = []
        for x in 0..<width {
            let (r, g, b) = bitmap.rgb(x, y)
            if b > 55, g > 55, b > r * 1.08, abs(g - b) < 80 {
                if run.last.map({ x - $0 <= 2 }) == true { run.append(x) }
                else {
                    if !run.isEmpty { runs.append(run) }
                    run = [x]
                }
            }
        }
        if !run.isEmpty { runs.append(run) }
        let relaxed = runs.filter { $0.last! - $0.first! >= width / 5 }
        if let row = relaxed.first,
           let left = row.first, let right = row.last {
            return ["y": Double(y) / Double(height),
                    "left": Double(left) / Double(width),
                    "right": Double(right) / Double(width)]
        }
    }
    return nil
}

/// The highway meets the dark sky at a narrow dark edge band. Find that
/// boundary near Turbo's feet, away from the right-hand meter.
func roadEdge(_ bitmap: Picture, yFraction: Double = 0.74) -> [String: Any]? {
    let width = bitmap.width, height = bitmap.height
    let row = Int(Double(height) * yFraction)
    for threshold in [10, 16, 22] {
        var run = [Int]()
        for x in 0..<(width / 2) {
            let (r, g, b) = bitmap.rgb(x, row)
            if r - b >= Double(threshold), g <= r {
                if run.last.map({ x - $0 <= 2 }) == true { run.append(x) }
                else {
                    if run.count >= 4 { return ["y": Double(row) / Double(height), "x": run.first!] }
                    run = [x]
                }
            }
        }
        if run.count >= 4 { return ["y": Double(row) / Double(height), "x": run.first!] }
    }
    return nil
}

/// Find Turbo from the small purple shell and its two white eyes. The purple
/// HUD tube and purple road objects never have two eyes immediately above.
func findSnail(_ bitmap: Picture) -> [String: Any]? {
    let width = bitmap.width, height = bitmap.height
    let left = Int(Double(width) * 0.10), right = Int(Double(width) * 0.82)
    var masks = Set<Int>()
    for y in Int(Double(height) * 0.68)..<Int(Double(height) * 0.82) {
        for x in left..<right {
            let (r, g, b) = bitmap.rgb(x, y)
            if b > 45, r > b * 0.78, b > g * 1.02 { masks.insert(y * width + x) }
        }
    }
    var components = [(x: Double, y: Int, n: Int, w: Int, h: Int, bottom: Int)]()
    var seen = Set<Int>()
    for y in Int(Double(height) * 0.68)..<Int(Double(height) * 0.82) {
        for x in left..<right {
            let seed = y * width + x
            guard masks.contains(seed), !seen.contains(seed) else { continue }
            var stack = [seed], area = 0, minX = x, maxX = x, minY = y, maxY = y
            seen.insert(seed)
            while let at = stack.popLast() {
                let px = at % width, py = at / width
                area += 1; minX = min(minX, px); maxX = max(maxX, px)
                minY = min(minY, py); maxY = max(maxY, py)
                for (dx, dy) in [(1,0), (-1,0), (0,1), (0,-1)] {
                    let nx = px + dx, ny = py + dy, next = ny * width + nx
                    if nx >= left, nx < right, masks.contains(next), !seen.contains(next) {
                        seen.insert(next); stack.append(next)
                    }
                }
            }
            let boxWidth = maxX - minX + 1, boxHeight = maxY - minY + 1
            if area >= 7, boxWidth >= 4, boxWidth <= width / 3, boxHeight >= 3 {
                components.append((Double(minX + maxX) / 2, minY, area, boxWidth, boxHeight, maxY))
            }
        }
    }
    // The procedural shell is the largest purple mass on screen, while the
    // retail shell has a bright inner patch and sits in a much smaller set.
    if let shell = components.max(by: { $0.n < $1.n }) {
        if shell.w >= 18 && shell.h >= 10 {
            return ["x": shell.x / Double(width), "y": Double(shell.y) / Double(height),
                    "pixels": shell.n, "width": shell.w, "height": shell.h,
                    "bottom": Double(shell.bottom) / Double(height)]
        }
    }
    let shells = components.filter {
        $0.w >= 7 && $0.h >= 4 && Double($0.y) > Double(height) * 0.70
    }
    guard let winner = shells.min(by: { $0.w > $1.w }) else { return nil }
    return ["x": winner.x / Double(width), "y": Double(winner.y) / Double(height),
            "pixels": winner.n, "width": winner.w, "height": winner.h,
            "bottom": Double(winner.bottom) / Double(height)]
}

func roadCentre(_ bitmap: Picture) -> Double? {
    let width = bitmap.width, height = bitmap.height
    var centres: [Double] = []
    for fraction in [0.55, 0.64, 0.72, 0.80] {
        let y = Int(Double(height) * fraction)
        var xs: [Int] = []
        for x in 0..<width {
            let (r, g, b) = bitmap.rgb(x, y)
            if b > 70, g > 70, b > r * 1.18, abs(g - b) < 65 { xs.append(x) }
        }
        guard !xs.isEmpty else { continue }
        var start = 0
        var bestLeft: Int?, bestRight: Int?
        for i in 1...max(1, xs.count) {
            if i >= xs.count || xs[i] > xs[i - 1] + 8 {
                if xs[i - 1] - xs[start] > (bestRight ?? 0) - (bestLeft ?? 0) {
                    bestLeft = xs[start]; bestRight = xs[i - 1]
                }
                if i < xs.count { start = i }
            }
        }
        if let left = bestLeft, let right = bestRight, right - left >= width / 7 {
            centres.append(Double(left + right) / Double(width * 2))
        }
    }
    return centres.isEmpty ? nil : centres.max { abs($0 - 0.5) < abs($1 - 0.5) }
}

/// Across the road, two cells in a row have the same blue-orange tone. Their
/// span gives a half-width without needing to see both viewport edges.
func roadSpan(_ bitmap: Picture) -> [String: Any]? {
    let width = bitmap.width, height = bitmap.height
    var found = [(y: Double, x: Double, span: Int)]()
    for fraction in [0.73, 0.74, 0.75, 0.76] {
        let row = Int(Double(height) * fraction)
        var faces = [(Double, Int)]()
        for x in 0..<width {
            let (r, g, b) = bitmap.rgb(x, row)
            if b >= r, g >= r, b - r >= 35, abs(g - b) <= 24 { faces.append((r, x)) }
        }
        var start = 0
        while start < faces.count {
            var end = start
            while end + 1 < faces.count, faces[end + 1].1 - faces[end].1 <= 3 { end += 1 }
            var near = [(Int, Int)]()
            for i in start...end where abs(faces[i].0 - faces[start].0) <= 2 {
                let x = faces[i].1
                if let last = near.last, x - last.1 <= 2 { near[near.count - 1] = (last.0, x) }
                else { near.append((x, x)) }
            }
            for i in 0..<near.count {
                for j in (i + 1)..<near.count where near[j].0 - near[i].1 >= width / 16 {
                    found.append((fraction, Double(near[i].0 + near[j].0) / 2,
                                  near[j].0 - near[i].1 + 1))
                    break
                }
            }
            start = end + 1
        }
    }
    guard let widest = found.max(by: { $0.span < $1.span }) else { return nil }
    return ["y": widest.y, "x": widest.x / Double(width),
            "halfWidthFraction": Double(widest.span) / Double(width * 2)]
}

for path in CommandLine.arguments.dropFirst(2) {
    guard let reading = read(path),
          let data = try? JSONSerialization.data(withJSONObject: reading),
          let text = String(data: data, encoding: .utf8) else { continue }
    lines.append(text)
}
try lines.joined(separator: "\n").appending("\n")
    .write(to: output, atomically: true, encoding: .utf8)
print("read \(lines.count) frames -> \(output.path)")
