import SwiftUI

/// Every screen the app can push on top of the title menu. Keeping them in one
/// enum lets the stack be driven programmatically, which is what the results
/// screen's MENU button needs: popping a route always works, whereas the
/// environment `dismiss` silently does nothing when the race is the root view.
enum AppRoute: Hashable {
    case galaxy
    case game(mode: GameMode, level: Int)
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
    /// map and `-autostart <mode>` (optionally with `-level N`) launches straight
    /// into a race. Only compiled into debug builds so shipping builds always
    /// open on the menu.
    private static func debugLaunchPath() -> [AppRoute] {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-showgalaxy") { return [.galaxy] }
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
