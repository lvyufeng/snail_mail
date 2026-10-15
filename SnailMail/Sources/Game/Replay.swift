import Foundation

/// A recording of one Time Trial, kept for the retail build's `Watch Replay`
/// row.
///
/// The row (`0x4a3778`) is built on the Time Trial screen (`0x416136`) and is
/// only put up while the build's replay buffer holds a run: `0x416151` reads
/// the buffer and calls `0x4010e0` on the row when it is empty, and `0x41607a`
/// shifts `Play` to x = 250 to make room for it when it is not. Selecting it
/// posts the buffer to the game — `0x416683` sets the "playing a replay" flag
/// and `0x416697` hands over the buffer's pointer — and the run is played back.
///
/// The remake records the snail's own line rather than raw touches: a sample
/// every few units of route carrying where he sat across the road and whether
/// he was holding fire. Playback reads that line back by distance, so the run
/// reproduces itself whatever the frame rate is doing on the day.
struct ReplayTrace: Codable {
    struct Sample: Codable {
        /// How far up the route the snail had got, in the scene's own units.
        var distance: Double
        /// Where he sat across the road, -1...1.
        var lateral: Double
        /// Whether he was holding fire.
        var firing: Bool
    }

    var mode: String
    var level: Int
    /// The `Track:` number the run was laid out with, so a replay wears the
    /// same road surface and plays the same music.
    var track: Int
    /// The seed the course was built from, so a replay meets the same hazards
    /// in the same places.
    var seed: UInt64
    /// The score the run finished on. The best run is the one kept.
    var score: Int
    var samples: [Sample]

    /// How long the recording ran, in world units.
    var length: Double { samples.last?.distance ?? 0 }
}

/// Keeps the one replay the `Watch Replay` row plays back. The retail build
/// holds a single buffer rather than one per mode, so this does too.
final class ReplayStore {
    static let shared = ReplayStore()

    /// The mode the row belongs to. Only a Time Trial is recorded, so this is
    /// the only mode a stored trace can carry.
    static let recordedMode = GameMode.speedRun

    private let defaults: UserDefaults
    private static let key = "replay.watch"

    private(set) var trace: ReplayTrace?

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key) {
            trace = try? JSONDecoder().decode(ReplayTrace.self, from: data)
        }
    }

    /// True while there is a run to put the `Watch Replay` row up for.
    var hasReplay: Bool { trace?.samples.isEmpty == false }

    /// The row is only meaningful for the mode that records, so a trace from
    /// anywhere else reads as no replay at all.
    func hasReplay(for mode: GameMode) -> Bool {
        hasReplay && trace?.mode == mode.rawValue
    }

    /// Files a finished run. A run only replaces the one on file when it
    /// scored at least as well, so the row plays back the best trial so far.
    func offer(_ candidate: ReplayTrace) {
        guard !candidate.samples.isEmpty else { return }
        if let current = trace, current.score > candidate.score { return }
        trace = candidate
        if let data = try? JSONEncoder().encode(candidate) {
            defaults.set(data, forKey: Self.key)
        }
    }

    /// Drops the recording. Only used by the screenshot hooks, which want to
    /// photograph the row in its empty state.
    func clear() {
        trace = nil
        defaults.removeObject(forKey: Self.key)
    }
}
