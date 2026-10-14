import SwiftUI
import SpriteKit

struct GameView: View {
    let mode: GameMode
    let level: Int
    /// Leaves the race for the screen below it. Supplied by the navigation
    /// stack so the results screen's MENU works even when the race is the root.
    let onMenu: () -> Void
    @StateObject private var model: GameViewModel

    init(mode: GameMode, level: Int = 0, onMenu: @escaping () -> Void) {
        self.mode = mode
        self.level = level
        self.onMenu = onMenu
        _model = StateObject(wrappedValue: GameViewModel(mode: mode, level: level))
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
                })

                if case .finished(let won) = model.state.phase {
                    ResultOverlay(won: won, state: model.state,
                                  mode: mode, levelName: levelName,
                                  onReplay: { model.restart() },
                                  onMenu: onMenu)
                }
            }
            .onAppear {
                model.scene.size = geo.size
                Sound.shared.start()
            }
        }
        .statusBarHidden()
    }

    /// The name the results screen files a high score under.
    private var levelName: String {
        guard mode == .arcade,
              let star = LevelCatalog.arcade.first(where: { $0.id == level })
        else { return mode.title }
        return star.name
    }
}

final class GameViewModel: ObservableObject {
    @Published var state = RaceState()
    let scene: GameScene

    init(mode: GameMode, level: Int) {
        scene = GameScene(mode: mode, level: level, size: CGSize(width: 800, height: 360))
        #if DEBUG
        scene.autoStart = ProcessInfo.processInfo.arguments.contains("-autostart")
        #endif
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
