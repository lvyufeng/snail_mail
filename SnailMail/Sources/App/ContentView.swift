import SwiftUI

struct ContentView: View {
    /// Debug hook used for automated screenshots: `-autostart tutorial`.
    /// Only compiled into debug builds so shipping builds always show the menu.
    private var autoMode: GameMode? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-autostart"), i + 1 < args.count else { return nil }
        return GameMode(rawValue: args[i + 1])
        #else
        return nil
        #endif
    }

    var body: some View {
        if let mode = autoMode {
            GameView(mode: mode)
        } else {
            NavigationStack {
                MenuView()
            }
        }
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
