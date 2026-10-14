import Foundation

/// The start screen's `Select Speed >` and `Select Difficulty >` cyclers.
///
/// The retail build lets the player dial the campaign's own `Speed:` reading
/// and how often its `Salt:`/`Garbage:` hazards roll before a Postal run. The
/// remake keeps those two knobs, applies them as multipliers on top of each
/// level's own numbers, and remembers them between launches.
final class GameSettings: ObservableObject {
    static let shared = GameSettings()

    enum Speed: String, CaseIterable, Identifiable {
        case slow, normal, fast, insane

        var id: String { rawValue }

        var label: String {
            switch self {
            case .slow: "SLOW"
            case .normal: "NORMAL"
            case .fast: "FAST"
            case .insane: "INSANE"
            }
        }

        var chinese: String {
            switch self {
            case .slow: "慢速"
            case .normal: "标准"
            case .fast: "快速"
            case .insane: "疯狂"
            }
        }

        /// Multiplier on the level's own speed reading.
        var scale: Double {
            switch self {
            case .slow: 0.75
            case .normal: 1
            case .fast: 1.25
            case .insane: 1.5
            }
        }
    }

    enum Difficulty: String, CaseIterable, Identifiable {
        case easy, normal, hard

        var id: String { rawValue }

        var label: String {
            switch self {
            case .easy: "EASY"
            case .normal: "NORMAL"
            case .hard: "HARD"
            }
        }

        var chinese: String {
            switch self {
            case .easy: "简单"
            case .normal: "标准"
            case .hard: "困难"
            }
        }

        /// Multiplier on the level's own salt and garbage probabilities.
        var scale: Double {
            switch self {
            case .easy: 0.6
            case .normal: 1
            case .hard: 1.5
            }
        }
    }

    @Published var speed: Speed {
        didSet { defaults.set(speed.rawValue, forKey: Key.speed) }
    }

    @Published var difficulty: Difficulty {
        didSet { defaults.set(difficulty.rawValue, forKey: Key.difficulty) }
    }

    private let defaults: UserDefaults

    private enum Key {
        static let speed = "arcadeSpeed"
        static let difficulty = "arcadeDifficulty"
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        speed = Speed(rawValue: defaults.string(forKey: Key.speed) ?? "") ?? .normal
        difficulty = Difficulty(rawValue: defaults.string(forKey: Key.difficulty) ?? "") ?? .normal
    }

    var speedScale: Double { speed.scale }
    var difficultyScale: Double { difficulty.scale }

    func cycleSpeed(by step: Int) {
        let all = Speed.allCases
        let index = all.firstIndex(of: speed) ?? 0
        speed = all[((index + step) % all.count + all.count) % all.count]
    }

    func cycleDifficulty(by step: Int) {
        let all = Difficulty.allCases
        let index = all.firstIndex(of: difficulty) ?? 0
        difficulty = all[((index + step) % all.count + all.count) % all.count]
    }
}
