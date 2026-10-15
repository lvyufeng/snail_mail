import SwiftUI
import SpriteKit

struct GameView: View {
    let mode: GameMode
    let level: Int
    /// The recording to play back, when this screen is the retail build's
    /// `Watch Replay` (`0x4a3778`). A replay runs to the end of the recording
    /// and then hands the player back to the screen below.
    let replay: ReplayTrace?
    /// Leaves the race for the screen below it. Supplied by the navigation
    /// stack so the results screen's MENU works even when the race is the root.
    let onMenu: () -> Void
    @StateObject private var model: GameViewModel
    @EnvironmentObject private var router: AppRouter
    /// The retail build ends a run on two pages: the results, then the
    /// `Thanks For Playing!` page. This tracks which of the two is up.
    /// `-thanks` opens straight on the second page for screenshots.
    @State private var showingThanks = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-thanks")
        #else
        return false
        #endif
    }()

    init(mode: GameMode, level: Int = 0, replay: ReplayTrace? = nil,
         onMenu: @escaping () -> Void) {
        self.mode = mode
        self.level = level
        self.replay = replay
        self.onMenu = onMenu
        _model = StateObject(wrappedValue: GameViewModel(mode: mode, level: level,
                                                         replay: replay))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SpriteView(scene: model.scene, options: [.ignoresSiblingOrder])
                    .ignoresSafeArea()
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let fraction = (value.location.x / geo.size.width) * 2 - 1
                                model.scene.steer(toFraction: max(-1, min(1, fraction)))
                                model.scene.setTouching(true)
                            }
                            .onEnded { _ in
                                model.scene.setTouching(false)
                            }
                    )

                HUDView(state: model.state, mode: mode, onPrimary: {
                    model.primaryAction()
                }, onPause: {
                    model.scene.togglePause()
                }, onOptions: {
                    // The original's pause overlay opens the same options
                    // screen the title menu does, over the held race.
                    router.push(.options)
                }, onEndGame: {
                    // `End Game` abandons the run rather than finishing it, so
                    // the race is dropped without a results page.
                    Sound.shared.setPostalAlarm(false)
                    onMenu()
                })

                if case .finished(let won) = model.state.phase {
                    if replay != nil {
                        ReplayOverlay { onMenu() }
                    } else if showingThanks {
                        ThanksOverlay(mode: mode) {
                            showingThanks = false
                            onMenu()
                        }
                    } else {
                        ResultOverlay(won: won, state: model.state,
                                      mode: mode, levelName: levelName,
                                      onReplay: {
                                          showingThanks = false
                                          model.restart()
                                      },
                                      onMenu: { showingThanks = true })
                    }
                }

                if replay != nil {
                    ReplayBadge()
                }
            }
            .onAppear {
                model.scene.size = geo.size
                Sound.shared.start()
            }
        }
        // The race owns the whole screen: the HUD is laid out against the
        // retail build's 640x480 frame, so it has to see the frame's real
        // height rather than the height left over under a navigation bar.
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden()
    }

    /// The name the results screen files a high score under.
    private var levelName: String {
        guard mode == .arcade else { return mode.title }
        return LevelCatalog.star(level).name
    }
}

final class GameViewModel: ObservableObject {
    @Published var state = RaceState()
    let scene: GameScene

    init(mode: GameMode, level: Int, replay: ReplayTrace? = nil) {
        scene = GameScene(mode: mode, level: level,
                          size: CGSize(width: 800, height: 360), replay: replay)
        if replay != nil { scene.autoStart = true }
        #if DEBUG
        if replay == nil {
            scene.autoStart = ProcessInfo.processInfo.arguments.contains("-autostart")
        }
        #endif
        scene.onReplayRecorded = { ReplayStore.shared.offer($0) }
        scene.onStateChange = { [weak self] newState in
            DispatchQueue.main.async { self?.state = newState }
        }
    }

    func primaryAction() {
        switch state.phase {
        case .ready: scene.startRace()
        case .paused: scene.togglePause()
        case .running: break
        case .finished: restart()
        }
    }

    func restart() {
        scene.restartRace()
    }
}
