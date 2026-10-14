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

    /// Debug hook matching `-autostart`: `-level N` selects a campaign star.
    private var autoLevel: Int {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-level"), i + 1 < args.count,
              let value = Int(args[i + 1]) else { return 0 }
        return value
        #else
        return 0
        #endif
    }

    var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-showgalaxy") {
            NavigationStack { LevelSelectView() }
        } else if let mode = autoMode {
            GameView(mode: mode, level: autoLevel)
        } else {
            NavigationStack { MenuView() }
        }
        #else
        if let mode = autoMode {
            GameView(mode: mode, level: autoLevel)
        } else {
            NavigationStack {
                MenuView()
            }
        }
        #endif
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
