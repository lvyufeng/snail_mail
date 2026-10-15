import SwiftUI

/// Title screen. The retail build's `0x419b30` fills it with exactly five rows
/// — `New Game` (0x4a3b74), `High Scores` (0x4a3b68), `Options` (0x4a3b60),
/// `Credits` (0x4a3b58) and `Exit` (0x4a20f4) — and nothing else; `Help` and
/// the mode list live one screen deeper (see `ModeSelectView`). The remake
/// keeps that shape and adds the Chinese sub-labels the rest of the UI uses.
struct MenuView: View {
    @EnvironmentObject private var router: AppRouter
    @State private var confirmingQuit = false

    var body: some View {
        MenuScaffold {
            NeonPanel(border: Palette.magenta) {
                VStack(spacing: 10) {
                    MenuRow(title: "New Game", chinese: "开始游戏",
                            subtitle: "Tutorial, Postal, Time Trial and Challenge",
                            icon: "▶") { router.push(.modes) }
                    MenuRow(title: "High Scores", chinese: "排行榜",
                            subtitle: "Your best runs", icon: "★") {
                        router.push(.highScores)
                    }
                    MenuRow(title: "Options", chinese: "设置",
                            subtitle: "Sound and music", icon: "⚙") {
                        router.push(.options)
                    }
                    MenuRow(title: "Credits", chinese: "制作名单",
                            subtitle: "Who made this", icon: "✎") {
                        router.push(.credits)
                    }
                    MenuRow(title: "Exit", chinese: "退出",
                            subtitle: "Leave the game", icon: "⏻") {
                        confirmingQuit = true
                    }
                }
            }
            .padding(.horizontal, 20)

            Text("Drag to steer * hold to fire * dodge salt and meteors")
                .font(.retail(13, weight: .medium))
                .foregroundStyle(Palette.ink.opacity(0.72))
                .multilineTextAlignment(.center)
                .padding(.bottom, 44)
        }
        .overlay {
            if confirmingQuit {
                QuitConfirmOverlay(
                    onYes: { exit(0) },
                    onNo: { confirmingQuit = false }
                )
            }
        }
        .onAppear {
            #if DEBUG
            // `-quitconfirm`: open the leave-the-game question straight away
            // so it can be screenshotted without a tap.
            if ProcessInfo.processInfo.arguments.contains("-quitconfirm") {
                confirmingQuit = true
            }
            #endif
        }
    }
}

/// The retail build's mode list (`0x417bc0`): `Tutorial` (0x4a38e4),
/// `Postal Mode` (0x4a38d8), `Time Trial` (0x4a38cc), `Challenge Mode`
/// (0x4a38bc), then `Help` (0x4a38b4) and `Back` (0x4a20ec). The two Time
/// Trial percentage rows are built here too (`0x415f30`), so they sit under
/// the Time Trial entry rather than on the title screen.
struct ModeSelectView: View {
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var settings = GameSettings.shared
    @State private var selected: GameMode = .tutorial

    /// The retail order: Tutorial first, then the modes in their own table.
    private let order: [GameMode] = [.tutorial, .arcade, .speedRun, .challenge]

    var body: some View {
        MenuScaffold {
            NeonPanel(border: Palette.magenta) {
                VStack(spacing: 10) {
                    ForEach(order) { mode in
                        ModeRow(mode: mode, isSelected: selected == mode) {
                            selected = mode
                            Sound.shared.play(.select)
                        }
                    }
                    MenuRow(title: "Help", chinese: "帮助",
                            subtitle: "Controls and hazards", icon: "❓") {
                        router.push(.help)
                    }
                    MenuRow(title: "Back", chinese: "返回",
                            subtitle: "Back to the title screen", icon: "◀") {
                        router.pop()
                    }
                }
            }
            .padding(.horizontal, 20)

            // The Time Trial screen's two percentage rows (`Select Speed`
            // 0x4a3788, `Select Difficulty` 0x4a37a4) step 20 points a press
            // and hand their reading to the level they start.
            if selected == .speedRun {
                NeonPanel(border: Palette.cyan) {
                    VStack(spacing: 8) {
                        SteppedRow(title: "Select Speed", value: settings.speedLabel,
                                   detail: "速度") {
                            settings.stepSpeed(by: -1)
                            Sound.shared.play(.select)
                        } next: {
                            settings.stepSpeed(by: 1)
                            Sound.shared.play(.select)
                        }
                        SteppedRow(title: "Select Difficulty", value: settings.difficultyLabel,
                                   detail: "难度") {
                            settings.stepDifficulty(by: -1)
                            Sound.shared.play(.select)
                        } next: {
                            settings.stepDifficulty(by: 1)
                            Sound.shared.play(.select)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            // The campaign opens on the galaxy map so the player picks a star;
            // every other mode starts its own route.
            if selected == .arcade {
                Button {
                    router.push(.galaxy)
                } label: {
                    ArcadeLabel(title: "SELECT STAR", tint: Palette.good, icon: "★")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 60)
            } else {
                Button {
                    router.push(.game(mode: selected, level: 0))
                } label: {
                    ArcadeLabel(title: "PLAY", tint: Palette.good, icon: "▶")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 60)
            }

            Text("Drag to steer * hold to fire * dodge salt and meteors")
                .font(.retail(13, weight: .medium))
                .foregroundStyle(Palette.ink.opacity(0.72))
                .multilineTextAlignment(.center)
                .padding(.bottom, 44)
        }
        .onAppear {
            #if DEBUG
            // `-select <mode>`: land on a mode row so the screen behind it
            // (the percentage rows on Time Trial) can be screenshotted too.
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-select"), i + 1 < args.count,
               let mode = GameMode(rawValue: args[i + 1]) {
                selected = mode
            }
            #endif
        }
    }
}

/// The chrome the title screen and the mode list share: the deep-space
/// backdrop, the game's masthead, the mute control and a scrolling column.
private struct MenuScaffold<Content: View>: View {
    @State private var muted = Sound.shared.muted
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            RetailBackdrop(stem: "menubg")

            GeometryReader { geo in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        masthead
                        content
                    }
                    .frame(maxWidth: 420)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geo.size.height)
                    .padding(.horizontal, 20)
                }
            }

            VStack {
                HStack {
                    Spacer()
                    RoundIconButton(icon: .sound(on: !muted)) {
                        muted.toggle()
                        Sound.shared.setMuted(muted)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
        .onAppear {
            Sound.shared.start()
            Sound.shared.playMusic(.menu)
        }
    }

    private var masthead: some View {
        VStack(spacing: 18) {
            SnailMascot()
                .frame(width: 170, height: 130)
                .shadow(color: Palette.magenta.opacity(0.5), radius: 18, y: 6)
                .padding(.top, 34)

            VStack(spacing: 2) {
                Text("SNAIL MAIL")
                    .font(.retail(46, weight: .black))
                    .tracking(1)
                    .foregroundStyle(
                        LinearGradient(colors: [Palette.gold, Palette.goldDeep],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .shadow(color: .black.opacity(0.8), radius: 6, y: 3)
                Text("蜗牛竞速 · Intergalactic Delivery")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.ink.opacity(0.8))
            }
        }
    }
}

/// The build's own leave-the-game question. Its `Exit` entry puts up a dimmed
/// screen carrying `Do you really want to quit?` (0x4a16ac) over a `Yes`
/// (0x4a16c8) and a `No` (0x4a16a8) button, and only `Yes` closes the game.
private struct QuitConfirmOverlay: View {
    let onYes: () -> Void
    let onNo: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            NeonPanel(border: Palette.danger) {
                VStack(spacing: 18) {
                    Text("Do you really want to quit?")
                        .font(.retail(20, weight: .black))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 14) {
                        ArcadeButton(title: "YES", tint: Palette.danger, action: onYes)
                        ArcadeButton(title: "NO", tint: Palette.good, action: onNo)
                    }
                }
                // Without a width the two pills take the whole screen, and
                // their labels go off the edges with them.
                .frame(maxWidth: 260)
            }
            .padding(.horizontal, 40)
        }
    }
}

private struct ModeRow: View {
    let mode: GameMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle()
                    .stroke(Palette.ink.opacity(0.7), lineWidth: 2)
                    .background(
                        Circle().fill(isSelected ? Palette.cyan : Color.clear)
                            .padding(3)
                    )
                    .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(mode.title)
                            .font(.retail(18, weight: .heavy))
                            .foregroundStyle(.white)
                        Text(mode.chinese)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Palette.gold)
                    }
                    Text(mode.subtitle)
                        .font(.retail(11, weight: .medium))
                        .foregroundStyle(Palette.ink.opacity(0.6))
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Palette.magenta.opacity(0.28) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Palette.cyan.opacity(0.9) : Palette.ink.opacity(0.15),
                            lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// A plain menu entry for screens that only navigate: an icon disc, the title,
/// its Chinese label and a trailing chevron. Same chrome as `ModeRow` so the
/// two lists read as one product.
private struct MenuRow: View {
    let title: String
    let chinese: String
    let subtitle: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(icon)
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Palette.cyan.opacity(0.28)))
                    .overlay(Circle().stroke(Palette.cyan.opacity(0.8), lineWidth: 1.2))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.retail(18, weight: .heavy))
                            .foregroundStyle(.white)
                        Text(chinese)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Palette.gold)
                    }
                    Text(subtitle)
                        .font(.retail(11, weight: .medium))
                        .foregroundStyle(Palette.ink.opacity(0.6))
                }
                Spacer(minLength: 8)
                Text("›")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(Palette.cyan.opacity(0.9))
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Palette.ink.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
