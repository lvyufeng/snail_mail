import Foundation

/// The retail build's four percentage rows: `Select Difficulty` and
/// `Select Speed` on the Time Trial screen (0x415fb6, 0x416034) and
/// `Music Volume` / `Sounds Volume` on Options (0x41ae1b, 0x41ad97). All four
/// are the same widget — a border carrying a `%02i%%` readout (format string
/// 0x4a10f4) — and its update routine at 0x403152 steps the value by 0.2
/// (`0x497270`) and snaps the ends: at or above 0.9 (`0x49726c`) the row jumps
/// to 1.0, at or below 0.1 (`0x497258`) it drops to 0.0 (`0x497234`). The rows
/// therefore only ever read 0, 20, 40, 60, 80 or 100 per cent. The build's own
/// init (`0x406c89`) starts both of its settings on `0x28` — 40 per cent — and
/// the Time Trial screen hands that reading to the level it starts.
final class GameSettings: ObservableObject {
    static let shared = GameSettings()

    /// One button press moves a row by this much, the 0.2 the border update
    /// adds and subtracts.
    static let percentStep = 20
    /// Where a fresh install starts both settings, `0x406c89`'s `0x28`.
    static let defaultPercent = 40

    @Published var speedPercent: Int {
        didSet { defaults.set(speedPercent, forKey: Key.speed) }
    }

    @Published var difficultyPercent: Int {
        didSet { defaults.set(difficultyPercent, forKey: Key.difficulty) }
    }

    private let defaults: UserDefaults

    private enum Key {
        static let speed = "arcadeSpeed"
        static let difficulty = "arcadeDifficulty"
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        speedPercent = Self.storedPercent(defaults, key: Key.speed, legacy: Self.legacySpeeds)
        difficultyPercent = Self.storedPercent(defaults, key: Key.difficulty,
                                              legacy: Self.legacyDifficulties)
    }

    /// The `%02i%%` readout the four rows print. The format pads to two digits,
    /// so a single-digit reading shows a leading zero — `05%`.
    static func percentLabel(_ percent: Int) -> String {
        String(format: "%02i%%", percent)
    }

    var speedLabel: String { Self.percentLabel(speedPercent) }
    var difficultyLabel: String { Self.percentLabel(difficultyPercent) }

    func stepSpeed(by steps: Int) {
        speedPercent = Self.stepped(speedPercent, by: steps)
    }

    func stepDifficulty(by steps: Int) {
        difficultyPercent = Self.stepped(difficultyPercent, by: steps)
    }

    /// One press of a row's `>` or `<` button, with the update routine's end
    /// snapping: a reading pushed to 90 or beyond becomes a full 100 and one
    /// pulled to 10 or below empties to 0.
    static func stepped(_ percent: Int, by steps: Int) -> Int {
        let moved = percent + steps * percentStep
        if moved >= 90 { return 100 }
        if moved <= 10 { return 0 }
        return min(100, max(0, moved))
    }

    /// How far the two readings scale a level's own numbers. The build turns a
    /// reading into a multiplier in 0x437e60 — `0.2 + 0.9 * p` — and hands it
    /// to the level it starts, so 40 per cent means 0.56 of a level's own
    /// speed and 100 per cent means 1.1 of it. The remake's levels are already
    /// tuned to the retail default, so a fresh install keeps the 1.0 it has
    /// always shipped with and the row scales from there.
    static func scale(forPercent percent: Int) -> Double {
        let retail = 0.2 + 0.9 * Double(percent) / 100
        let atDefault = 0.2 + 0.9 * Double(defaultPercent) / 100
        return retail / atDefault
    }

    var speedScale: Double { Self.scale(forPercent: speedPercent) }
    var difficultyScale: Double { Self.scale(forPercent: difficultyPercent) }

    private static func storedPercent(_ defaults: UserDefaults, key: String,
                                      legacy: [String: Int]) -> Int {
        // The first builds of the remake stored named steps here; a player
        // upgrading keeps the closest reading.
        if let name = defaults.string(forKey: key), let percent = legacy[name] {
            return percent
        }
        guard defaults.object(forKey: key) != nil else { return defaultPercent }
        return min(100, max(0, defaults.integer(forKey: key)))
    }

    private static let legacySpeeds = ["slow": 20, "normal": 40, "fast": 60, "insane": 80]
    private static let legacyDifficulties = ["easy": 20, "normal": 40, "hard": 60]
}
