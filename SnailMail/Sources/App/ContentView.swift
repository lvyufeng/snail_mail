import SwiftUI

struct ContentView: View {
    @StateObject private var router = AppRouter()

    var body: some View {
        NavigationStack(path: $router.path) {
            MenuView()
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .galaxy:
                        LevelSelectView()
                    case .game(let mode, let level):
                        GameView(mode: mode, level: level, onMenu: { router.pop() })
                    }
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
