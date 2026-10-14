import SwiftUI

/// The loader the 2005 build opens on, standing in for the seconds it spent
/// reading its data off the disc.
///
/// The original paints the game's logo over its title art and fills a gold bar
/// underneath while the level loads. The remake has nothing to load, so the bar
/// runs on a timer instead — long enough to read the logo, short enough that it
/// never stands between the player and the menu, and a tap skips it outright.
struct SplashView: View {
    /// Called once, when the bar has run its course or the player tapped past
    /// it. The caller is expected to fade this screen away.
    var onFinish: () -> Void

    /// How long the bar takes to cross the trough when nobody skips it.
    private let duration: Double = 1.5

    @State private var progress: CGFloat = 0
    @State private var finished = false

    var body: some View {
        ZStack {
            RetailBackdrop(stem: "splash")

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                logo
                Spacer(minLength: 0)
                trough
                    .padding(.horizontal, 56)
                    .padding(.bottom, 74)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .task { await run() }
    }

    /// The installer's own SNAIL MAIL lockup, keyed off its loading screen, or
    /// the mascot and title the menu uses when there is no retail folder.
    @ViewBuilder private var logo: some View {
        if let art = RetailAssets.billboardImage("Art/Baked/splashlogo.png") {
            Image(uiImage: art)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 264)
                .shadow(color: Palette.magenta.opacity(0.45), radius: 20, y: 6)
        } else {
            VStack(spacing: 10) {
                SnailMascot()
                    .frame(width: 170, height: 130)
                    .shadow(color: Palette.magenta.opacity(0.5), radius: 18, y: 6)
                Text("SNAIL MAIL")
                    .font(.retail(44, weight: .black))
                    .tracking(1)
                    .foregroundStyle(
                        LinearGradient(colors: [Palette.gold, Palette.goldDeep],
                                       startPoint: .top, endPoint: .bottom)
                    )
            }
        }
    }

    /// A dark trough with the gold run the build lights up inside it, with the
    /// `LOADING` label set in the original's own lettering beneath.
    private var trough: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(hex: "#360B2A"))
                        .overlay(
                            Capsule().stroke(Palette.gold.opacity(0.45), lineWidth: 1.5)
                        )
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#FFC52B"), Color(hex: "#FFE93D"),
                                         Color(hex: "#FFD24B")],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .frame(width: max(12, geo.size.width * progress))
                        .shadow(color: Palette.gold.opacity(0.6), radius: 6)
                }
            }
            .frame(height: 16)

            Text("LOADING")
                .font(.retail(15, weight: .bold))
                .tracking(4)
                .foregroundStyle(Palette.ink.opacity(0.7))
        }
    }

    private func run() async {
        withAnimation(.easeInOut(duration: duration)) { progress = 1 }
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }
}
