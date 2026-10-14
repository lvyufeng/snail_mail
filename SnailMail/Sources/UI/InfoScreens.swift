import SwiftUI

/// A shared chrome for the menu's side screens, so Help, Options, High Scores,
/// the intro crawl and the credits all read as the same product: the deep-space
/// backdrop with a titled neon panel on top.
private struct InfoScaffold<Content: View>: View {
    let title: String
    var chinese: String? = nil
    var icon: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            RetailBackdrop(stem: "help")

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    VStack(spacing: 3) {
                        if let icon { Text(icon).font(.system(size: 30)) }
                        Text(title)
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .tracking(0.5)
                            .foregroundStyle(
                                LinearGradient(colors: [Palette.gold, Palette.goldDeep],
                                               startPoint: .top, endPoint: .bottom)
                            )
                            .multilineTextAlignment(.center)
                            .shadow(color: .black.opacity(0.8), radius: 6, y: 3)
                        if let chinese {
                            Text(chinese)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(Palette.ink.opacity(0.75))
                        }
                    }
                    .padding(.top, 12)

                    NeonPanel(border: Palette.magenta) { content }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 40)
                }
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .statusBarHidden()
        .onAppear {
            Sound.shared.start()
            Sound.shared.playMusic(.menu)
        }
    }
}

/// The original's Help screen. The retail build painted its instructions into
/// a background bitmap; the remake states the same controls in words.
struct HelpView: View {
    private struct Item: Identifiable {
        let id = UUID()
        let keys: String
        let text: String
    }

    private let items: [Item] = [
        Item(keys: "DRAG LEFT / RIGHT", text: "Steer Turbo across the highway. Hold near an edge to hug that side of the road."),
        Item(keys: "TOUCH & HOLD", text: "Fire. Drive through a power-up ring to climb from the blaster to the laser and the rocket launcher."),
        Item(keys: "PARCELS {", text: "Pick up packages to fill the Parcel Collect gauge, then reach the Post Office to hand the quota in."),
        Item(keys: "SALT ^", text: "Salt burns and cannot be shot. Steer around it."),
        Item(keys: "ASTEROIDS & SLUGS", text: "They slow you down and knock you off the road — shoot them, or use a blast ring."),
        Item(keys: "GAPS", text: "A ramp carries you over a pit, and a jetpack carries you over the long ones. Fall in and you lose postal meter."),
        Item(keys: "POSTAL METER", text: "Your health, on the right. Hearts restore it; lose it all and you go postal."),
        Item(keys: "? RINGS", text: "Slow rings cost you speed. Yellow rings blow up nearby enemies."),
    ]

    var body: some View {
        InfoScaffold(title: "HELP", chinese: "操作说明", icon: "❓") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.keys)
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(Palette.cyan)
                        Text(item.text)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(Palette.ink.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The original's Options screen, kept to the two rows that mean something on
/// a phone: the music and sound-effect levels.
struct OptionsView: View {
    @State private var music: Double = Sound.shared.musicLevel
    @State private var sfx: Double = Sound.shared.sfxLevel
    @State private var muted: Bool = Sound.shared.muted

    var body: some View {
        InfoScaffold(title: "OPTIONS", chinese: "设置", icon: "⚙️") {
            VStack(spacing: 18) {
                VolumeRow(title: "Music Volume", value: $music) { Sound.shared.setMusicLevel($0) }
                VolumeRow(title: "Sounds Volume", value: $sfx) { Sound.shared.setSfxLevel($0) }

                Button {
                    muted.toggle()
                    Sound.shared.setMuted(muted)
                } label: {
                    HStack {
                        StatLabel(text: "Sound")
                        Spacer(minLength: 40)
                        Text(muted ? "Off" : "On")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(muted ? Palette.danger : Palette.good)
                    }
                }
                .buttonStyle(.plain)

                Text("The original's own music, effects and voice play when the retail assets are installed; without them the app falls back to synthesised audio.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.ink.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct VolumeRow: View {
    let title: String
    @Binding var value: Double
    let onChange: (Double) -> Void

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                StatLabel(text: title)
                Spacer(minLength: 40)
                Text("\(Int(value * 100))%")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.ink)
            }
            Slider(value: $value, in: 0...1)
                .tint(Palette.cyan)
                .onChange(of: value) { _, new in onChange(new) }
        }
    }
}

/// The original's two score tables, filled in when a run asks for a name.
struct HighScoresView: View {
    @ObservedObject private var scores = HighScores.shared

    var body: some View {
        InfoScaffold(title: "HIGH SCORES", chinese: "排行榜", icon: "🏆") {
            VStack(spacing: 20) {
                ForEach(HighScores.Board.allCases) { board in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            StatLabel(text: board.title, color: Palette.gold)
                            Spacer(minLength: 4)
                            Text(board.chinese)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(Palette.ink.opacity(0.6))
                        }
                        let rows = scores.entries(board)
                        if rows.isEmpty {
                            Text("No scores yet — deliver some mail!")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(Palette.ink.opacity(0.55))
                        } else {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                                ScoreRow(place: index + 1, entry: entry)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ScoreRow: View {
    let place: Int
    let entry: HighScoreEntry

    var body: some View {
        HStack(spacing: 10) {
            Text("\(place)")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(place == 1 ? Palette.gold : Palette.ink.opacity(0.7))
                .frame(width: 16, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !entry.level.isEmpty {
                    Text(entry.level)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Palette.ink.opacity(0.55))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            Text("\(entry.score)")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.ink)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 40)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }
}

/// The original's opening crawl (`INTRO/Intro.txt`), one text screen at a time,
/// stepped through with a tap. Picture inserts the retail script named are
/// dropped, so the story is told in words.
struct IntroView: View {
    @EnvironmentObject private var router: AppRouter
    @State private var index = 0

    private var slides: [String] { TrackData.introSlides }
    private var isLast: Bool { index >= slides.count - 1 }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Starfield()

            VStack {
                Spacer()
                Text(slides.isEmpty ? "SNAIL MAIL" : slides[min(index, slides.count - 1)])
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .foregroundStyle(Color(hex: "#FFE9A8"))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 34)
                    .shadow(color: .black.opacity(0.9), radius: 8)
                    .id(index)
                    .transition(.opacity)
                Spacer()
            }

            VStack {
                Spacer()
                Text(isLast ? "CLICK TO START" : "TAP TO CONTINUE")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(Palette.cyan.opacity(0.9))
                    .padding(.bottom, 40)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { advance() }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .statusBarHidden()
        .onAppear {
            Sound.shared.start()
            Sound.shared.playMusic(.intro)
        }
    }

    private func advance() {
        Sound.shared.play(.select)
        if isLast {
            router.pop()
        } else {
            withAnimation(.easeInOut(duration: 0.25)) { index += 1 }
        }
    }
}

/// The original's credits roll (`INTRO/Credits.txt`).
struct CreditsView: View {
    var body: some View {
        InfoScaffold(title: "CREDITS", chinese: "制作名单", icon: "🎬") {
            VStack(spacing: 16) {
                ForEach(Array(TrackData.creditsSlides.enumerated()), id: \.offset) { _, slide in
                    Text(slide)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.ink.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                Text("Remake: original art, audio and code. All original game data © its authors.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.ink.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
        }
    }
}
