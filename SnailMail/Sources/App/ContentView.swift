import SwiftUI

struct ContentView: View {
    @StateObject private var router = AppRouter()
    /// The launch splash covers the menu until it finishes or is tapped past.
    /// Debug launches open straight on their own screen instead.
    @State private var showSplash = !AppRouter.skipsSplash

    var body: some View {
        ZStack {
            NavigationStack(path: $router.path) {
                MenuView()
                    .navigationDestination(for: AppRoute.self) { route in
                        switch route {
                        case .modes:
                            ModeSelectView()
                        case .galaxy:
                            LevelSelectView()
                        case .briefing(let mode, let level):
                            BriefingView(mode: mode, level: level)
                        case .game(let mode, let level):
                            GameView(mode: mode, level: level, onMenu: { router.pop() })
                        case .replay:
                            GameView(mode: ReplayStore.recordedMode, level: 0,
                                     replay: ReplayStore.shared.trace,
                                     onMenu: { router.pop() })
                        case .help:
                            HelpView()
                        case .options:
                            OptionsView()
                        case .highScores:
                            HighScoresView()
                        case .intro:
                            IntroView()
                        case .credits:
                            CreditsView()
                        }
                    }
            }

            if showSplash {
                SplashView {
                    withAnimation(.easeOut(duration: 0.4)) { showSplash = false }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .environmentObject(router)
    }
}

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        var string = hex
        if string.hasPrefix("#") { string.removeFirst() }
        Scanner(string: string).scanHexInt64(&value)
        let r = Double((value & 0xFF0000) >> 16) / 255
        let g = Double((value & 0x00FF00) >> 8) / 255
        let b = Double(value & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
