import SwiftUI

/// Every screen the app can push on top of the title menu. Keeping them in one
/// enum lets the stack be driven programmatically, which is what the results
/// screen's MENU button needs: popping a route always works, whereas the
/// environment `dismiss` silently does nothing when the race is the root view.
enum AppRoute: Hashable {
    case galaxy
    /// The level's `GalaxyText:` briefing, shown between the map and the race
    /// the way the original prints it before a route starts.
    case briefing(mode: GameMode, level: Int)
    case game(mode: GameMode, level: Int)
    /// The menu's side screens, matching the original's button list.
    case help
    case options
    case highScores
    case intro
    case credits
}

/// Owns the single navigation stack. The title menu is the stack root, so any
/// screen — however it was reached — can hand control back with `pop()`.
@MainActor
final class AppRouter: ObservableObject {
    @Published var path: [AppRoute]

    init() {
        path = AppRouter.debugLaunchPath()
    }

    func push(_ route: AppRoute) {
        path.append(route)
    }

    /// Leave the current screen for the one beneath it, which is the title menu
    /// whenever the stack only holds a single route.
    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    /// Debug hooks used for automated screenshots: `-showgalaxy` opens the star
    /// map, `-screen <name>` opens one of the menu's side screens and
    /// `-autostart <mode>` (optionally with `-level N`) launches straight into a
    /// race. Only compiled into debug builds so shipping builds always open on
    /// the menu.
    private static func debugLaunchPath() -> [AppRoute] {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-showgalaxy") { return [.galaxy] }
        if let i = args.firstIndex(of: "-screen"), i + 1 < args.count {
            switch args[i + 1] {
            case "help": return [.help]
            case "options": return [.options]
            case "highscores": return [.highScores]
            case "intro": return [.intro]
            case "credits": return [.credits]
            default: return []
            }
        }
        guard let i = args.firstIndex(of: "-autostart"), i + 1 < args.count,
              let mode = GameMode(rawValue: args[i + 1]) else { return [] }
        let level = args.firstIndex(of: "-level").flatMap { j in
            j + 1 < args.count ? Int(args[j + 1]) : nil
        } ?? 0
        return [.game(mode: mode, level: level)]
        #else
        return []
        #endif
    }
}
