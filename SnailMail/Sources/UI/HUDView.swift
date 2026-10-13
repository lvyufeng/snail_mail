import SwiftUI

/// HUD: the "Postal Meter" (health, shown on the right like the original),
/// parcel quota, weapon tier, speed and time. Drawn entirely with the shared
/// theme kit so it matches the menu and the racer.
struct HUDView: View {
    let state: RaceState
    let mode: GameMode
    let onPrimary: () -> Void
    let onPause: () -> Void
    @State private var muted = Sound.shared.muted

    var body: some View {
        VStack {
            HStack(alignment: .top, spacing: 16) {
                NeonPanel(border: Palette.cyan) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            StatLabel(text: mode.title)
                            Text(mode.chinese)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Palette.gold.opacity(0.85))
                        }
                        HStack(spacing: 6) {
                            ParcelIcon()
                                .frame(width: 18, height: 22)
                            Text("\(state.parcels)\(state.quota > 0 ? " / \(state.quota)" : "")")
                                .font(.system(size: 20, weight: .heavy, design: .rounded))
                                .foregroundStyle(Palette.gold)
                        }
                        WeaponPips(level: state.weaponLevel, max: state.maxWeaponLevel)
                        Text(String(format: "%.0f km/h", state.speed / 40))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Palette.ink.opacity(0.85))
                    }
                    .padding(.horizontal, 2)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 8) {
                        RoundIconButton(glyph: muted ? "🔇" : "🔊") {
                            muted.toggle()
                            Sound.shared.setMuted(muted)
                        }
                        RoundIconButton(glyph: state.phase == .paused ? "▶" : "❚❚", action: onPause)
                    }
                    Text(String(format: "%.1fs", state.elapsed))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Palette.ink.opacity(0.85))
                    PostalMeter(fraction: state.meterFraction, invincible: state.invincible)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if mode == .tutorial, state.phase == .running {
                Text(tutorialHint)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
                    .overlay(Capsule().stroke(Palette.cyan.opacity(0.7), lineWidth: 1.5))
                    .padding(.top, 10)
                    .transition(.opacity)
            }

            Spacer()

            RouteProgress(progress: state.progress)

            if state.phase == .ready {
                VStack(spacing: 10) {
                    Text("DRAG to steer · HOLD to fire")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.ink.opacity(0.8))
                    Button(action: onPrimary) {
                        ArcadeLabel(title: "TAP TO START", tint: Palette.cyan)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: 260)
                }
                .padding(.bottom, 26)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state.phase)
    }

    private var tutorialHint: String {
        switch state.progress {
        case ..<0.18: "① Drag left / right to steer"
        case ..<0.4: "② Hold the screen to fire"
        case ..<0.62: "③ Fly through parcels to collect"
        case ..<0.85: "④ Grab rings to upgrade your weapon"
        default: "⑤ Reach the post office to deliver"
        }
    }
}

/// Vertical postal meter: a neon tube that fills from the bottom, tinted by how
/// much health is left.
private struct PostalMeter: View {
    let fraction: Double
    let invincible: Bool

    private var clamped: Double { min(1, max(0, fraction)) }
    private var fill: Color {
        switch clamped {
        case ..<0.3: Palette.danger
        case ..<0.6: Palette.gold
        default: Palette.good
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            StatLabel(text: "Postal")
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.5))
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(colors: [fill, fill.opacity(0.55)],
                                         startPoint: .top, endPoint: .bottom))
                    .padding(3)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .scaleEffect(y: clamped, anchor: .bottom)
                    .animation(.easeOut(duration: 0.2), value: clamped)
                if invincible {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Palette.cyan.opacity(0.35))
                }
            }
            .frame(width: 26, height: 150)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Palette.ink.opacity(0.6), lineWidth: 1.5)
            )
            .shadow(color: fill.opacity(0.6), radius: 8)
        }
    }
}

private struct WeaponPips: View {
    let level: Int
    let max: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i < level ? Palette.cyan : Palette.ink.opacity(0.2))
                    .frame(width: 16, height: 6)
            }
        }
    }
}

private struct RouteProgress: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.4))
                Capsule().fill(
                    LinearGradient(colors: [Palette.gold, Palette.goldDeep],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .frame(width: max(6, geo.size.width * progress))
            }
            .overlay(Capsule().stroke(Palette.ink.opacity(0.4), lineWidth: 1))
        }
        .frame(height: 8)
        .padding(.horizontal, 40)
        .padding(.bottom, 14)
    }
}
