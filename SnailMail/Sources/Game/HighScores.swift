import Foundation

/// One saved result, the way the retail build's `ScoreA/B/C.dat` tables keep
/// them: the name the player typed ("Enter your name here!") and the score it
/// was set with, plus the route it came from so the board reads as a history.
struct HighScoreEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var score: Int
    var level: String
}

/// The two score tables the original keeps — Postal and Challenge — each
/// trimmed to a top five and stored between launches.
final class HighScores: ObservableObject {
    static let shared = HighScores()

    enum Board: String, CaseIterable, Identifiable {
        case postal, challenge

        var id: String { rawValue }

        /// The heading the original prints above the table.
        var title: String {
            switch self {
            case .postal: "Postal High Scores"
            case .challenge: "Challenge High Scores"
            }
        }

        /// The shorter name the results page calls the same board by — its own
        /// heading over the run's tallies (`Postal Scores`, 0x4a37d8, and
        /// `Challenge Scores`, 0x4a37c4) — while the score screen keeps the
        /// `... High Scores` wording for the table itself.
        var resultsTitle: String {
            switch self {
            case .postal: "Postal Scores"
            case .challenge: "Challenge Scores"
            }
        }

        var chinese: String {
            switch self {
            case .postal: "战役排行榜"
            case .challenge: "挑战排行榜"
            }
        }

        var limit: Int { 5 }
    }

    @Published private(set) var postal: [HighScoreEntry]
    @Published private(set) var challenge: [HighScoreEntry]

    private let defaults: UserDefaults

    private enum Key {
        static let postal = "highScores.postal"
        static let challenge = "highScores.challenge"
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        postal = Self.load(defaults, Key.postal)
        challenge = Self.load(defaults, Key.challenge)
    }

    /// The table a mode feeds, or nil for the modes the original never scored.
    static func board(for mode: GameMode) -> Board? {
        switch mode {
        case .arcade: .postal
        case .challenge: .challenge
        default: nil
        }
    }

    func entries(_ board: Board) -> [HighScoreEntry] {
        board == .postal ? postal : challenge
    }

    /// True when a run would make the table, which is when the original asks
    /// for a name.
    func qualifies(_ board: Board, score: Int) -> Bool {
        guard score > 0 else { return false }
        let list = entries(board)
        return list.count < board.limit || score > (list.last?.score ?? 0)
    }

    /// Records a named run. Returns the place it landed (1-based), or nil when
    /// it did not survive the trim.
    @discardableResult
    func submit(_ board: Board, name: String, score: Int, level: String) -> Int? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = HighScoreEntry(name: trimmed.isEmpty ? "TURBO" : trimmed,
                                   score: score, level: level)
        var list = entries(board) + [entry]
        list.sort { $0.score > $1.score }
        list = Array(list.prefix(board.limit))
        store(list, board)
        return list.firstIndex(of: entry).map { $0 + 1 }
    }

    private func store(_ list: [HighScoreEntry], _ board: Board) {
        switch board {
        case .postal:
            postal = list
            save(list, Key.postal)
        case .challenge:
            challenge = list
            save(list, Key.challenge)
        }
    }

    private static func load(_ defaults: UserDefaults, _ key: String) -> [HighScoreEntry] {
        guard let data = defaults.data(forKey: key),
              let list = try? JSONDecoder().decode([HighScoreEntry].self, from: data)
        else { return [] }
        return list.sorted { $0.score > $1.score }
    }

    private func save(_ list: [HighScoreEntry], _ key: String) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        defaults.set(data, forKey: key)
    }
}
