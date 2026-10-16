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
                            .font(.retail(30, weight: .black))
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
        Item(keys: "TOUCH + HOLD", text: "Fire. Drive through a power-up ring to climb from the blaster to the laser and the rocket launcher."),
        Item(keys: "PARCELS", text: "Pick up packages to fill the Parcel Collect gauge, then reach the Post Office to hand the quota in."),
        Item(keys: "SALT", text: "Salt burns and cannot be shot. Steer around it."),
        Item(keys: "ASTEROIDS + SLUGS", text: "They slow you down and knock you off the road. Shoot them, or use a blast ring."),
        Item(keys: "GAPS", text: "A ramp carries you over a pit, and a jetpack carries you over the long ones. Fall in and you lose postal meter."),
        Item(keys: "JUMP POD", text: "Bounce off one of these to clear a gap a ramp would not reach."),
        Item(keys: "POSTAL METER", text: "Your health, on the right. Hearts restore it. Lose it all and you go postal."),
        Item(keys: "RINGS", text: "Slow rings cost you speed. Yellow rings blow up nearby enemies."),
    ]

    var body: some View {
        InfoScaffold(title: "HELP", chinese: "操作说明", icon: "❓") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.keys)
                            .font(.retail(12, weight: .heavy))
                            .foregroundStyle(Palette.cyan)
                        Text(item.text)
                            .font(.retail(14, weight: .medium))
                            .foregroundStyle(Palette.ink.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The original's Options screen (`0x41acc0`), kept to the two rows that mean
/// something on a phone. Retail labels them `     Sounds Volume     >`
/// (`0x4a3d30`) and `      Music Volume      >` (`0x4a3d14`) in that order,
/// and both are the shared stepped row (`0x403090`): the value lives 0...1,
/// one press moves it `0x3e4ccccd` (0.2), and the readout is `%02i%%`
/// (`0x4a10f4`) of `value * 100`. A fresh `SnailMail.cfg` ships both at
/// `0x3f19999a` (0.6), i.e. 60%.
struct OptionsView: View {
    @State private var music: Double = Sound.shared.musicLevel
    @State private var sfx: Double = Sound.shared.sfxLevel

    var body: some View {
        InfoScaffold(title: "OPTIONS", chinese: "设置", icon: "⚙️") {
            VStack(spacing: 18) {
                SteppedRow(title: "Sounds Volume", value: SteppedRow.percent(sfx),
                           detail: "音效") {
                    step(&sfx, by: -1) { Sound.shared.setSfxLevel($0) }
                    Sound.shared.play(.select)
                } next: {
                    step(&sfx, by: 1) { Sound.shared.setSfxLevel($0) }
                    Sound.shared.play(.select)
                }
                SteppedRow(title: "Music Volume", value: SteppedRow.percent(music),
                           detail: "音乐") {
                    step(&music, by: -1) { Sound.shared.setMusicLevel($0) }
                    Sound.shared.play(.select)
                } next: {
                    step(&music, by: 1) { Sound.shared.setMusicLevel($0) }
                    Sound.shared.play(.select)
                }

                Text("Music and effects are the remake's own, synthesised on the device.")
                    .font(.retail(11, weight: .medium))
                    .foregroundStyle(Palette.ink.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// One press of the retail arrow adds or removes `0.2` (`0x497270`) and the
    /// value stays on the `0, 0.2, ... 1.0` ladder the widget can produce.
    private func step(_ value: inout Double, by delta: Int, apply: (Double) -> Void) {
        let steps = (value * 5).rounded()
        let next = min(5, max(0, steps + Double(delta)))
        value = next / 5
        apply(value)
    }
}

/// The original's two score tables, filled in when a run asks for a name.
struct HighScoresView: View {
    @ObservedObject private var scores = HighScores.shared

    var body: some View {
        // The retail score screen titles itself `High Score Table`
        // (0x4a38a0, built at 0x417925) — the menu row that leads here is the
        // shorter `High Scores` (0x4a3b68). The scaffold headings are set in
        // caps like the rest of the chrome.
        InfoScaffold(title: "HIGH SCORE TABLE", chinese: "排行榜", icon: "🏆") {
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
                            Text("No scores yet. Deliver some mail!")
                                .font(.retail(13, weight: .medium))
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
                .font(.retail(13, weight: .black))
                .foregroundStyle(place == 1 ? Palette.gold : Palette.ink.opacity(0.7))
                .frame(width: 16, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.retail(15, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !entry.level.isEmpty {
                    Text(entry.level)
                        .font(.retail(10, weight: .medium))
                        .foregroundStyle(Palette.ink.opacity(0.55))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            Text("\(entry.score)")
                .font(.retail(16, weight: .heavy))
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
                    .font(.retail(20, weight: .semibold))
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
                    .font(.retail(13, weight: .heavy))
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
                        .font(.retail(15, weight: .semibold))
                        .foregroundStyle(Palette.ink.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                Text("Remake: original art, audio and code. All original game data (c) its authors.")
                    .font(.retail(11, weight: .medium))
                    .foregroundStyle(Palette.ink.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
        }
    }
}
