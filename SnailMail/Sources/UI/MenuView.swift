import SwiftUI

/// Title screen: pick a game mode and launch.
struct MenuView: View {
    @State private var selected: GameMode = .postal

    var body: some View {
        ZStack {
            // The original title art: a lit planet drifting through space.
            if let bg = UIImage(named: "menu_bg") {
                Image(uiImage: bg)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            } else {
                Color(hex: "#160029")
            }

            // Darken the top and bottom so the title and controls stay legible.
            LinearGradient(
                colors: [.black.opacity(0.40), .black.opacity(0.05), .black.opacity(0.45)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            StarfieldBackground()

            VStack(spacing: 24) {
                if let snail = UIImage(named: "snail") {
                    Image(uiImage: snail)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 132)
                        .shadow(color: .black.opacity(0.6), radius: 8, y: 4)
                }
                VStack(spacing: 6) {
                    Text("SNAIL MAIL")
                        .font(.system(size: 52, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [Color(hex: "#FFD24C"), Color(hex: "#FF8A3D")],
                                           startPoint: .top, endPoint: .bottom)
                        )
                        .shadow(color: .black.opacity(0.8), radius: 5, y: 3)
                    Text("蜗牛竞速 · Intergalactic delivery")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.7), radius: 3, y: 2)
                }

                VStack(spacing: 12) {
                    ForEach(GameMode.allCases) { mode in
                        ModeChip(mode: mode, isSelected: selected == mode) {
                            selected = mode
                        }
                    }
                }
                .frame(maxWidth: 340)

                NavigationLink {
                    GameView(mode: selected)
                } label: {
                    HStack(spacing: 10) {
                        if let play = UIImage(named: "play") {
                            Image(uiImage: play)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 26, height: 26)
                        }
                        Text("PLAY")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                    }
                    .frame(width: 220, height: 56)
                    .background(
                        LinearGradient(colors: [Color(hex: "#4CE07A"), Color(hex: "#1FA85A")],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .shadow(color: Color(hex: "#1FA85A").opacity(0.6), radius: 10, y: 5)
                }

                Text("Drag to steer · auto-fire · dodge salt & meteors")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding()
        }
    }
}

private struct ModeChip: View {
    let mode: GameMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20, weight: .bold))
                Text(mode.title)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                Spacer(minLength: 8)
                Text(mode.subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.trailing)
                    .opacity(0.8)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(isSelected ? Color(hex: "#3A6BFF") : Color.white.opacity(0.08))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.9) : Color.white.opacity(0.15), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Cheap animated starfield for the menu, all shape based.
struct StarfieldBackground: View {
    @State private var phase: CGFloat = 0
    private let stars: [(CGFloat, CGFloat, CGFloat, Double)] = (0..<80).map { _ in
        (CGFloat.random(in: 0...1), CGFloat.random(in: 0...1), CGFloat.random(in: 1...2.6), Double.random(in: 0.3...1))
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    for s in stars {
                        let y = (s.1 + CGFloat(t * 0.03 * s.3)).truncatingRemainder(dividingBy: 1)
                        let rect = CGRect(x: s.0 * size.width, y: y * size.height, width: s.2, height: s.2)
                        context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(s.3 * 0.8)))
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}
