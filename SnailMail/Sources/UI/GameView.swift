import SwiftUI
import SpriteKit

struct GameView: View {
    let mode: GameMode
    let level: Int
    @StateObject private var model: GameViewModel

    init(mode: GameMode, level: Int = 0) {
        self.mode = mode
        self.level = level
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
                    ResultOverlay(won: won, state: model.state) {
                        model.restart()
                    }
                }
            }
            .onAppear {
                model.scene.size = geo.size
                Sound.shared.start()
            }
        }
        .statusBarHidden()
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
        scene.startRace()
    }
}
