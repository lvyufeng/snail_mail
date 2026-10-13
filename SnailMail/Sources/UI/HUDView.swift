import SwiftUI

/// HUD: the "Postal Meter" (health, shown on the right like the original),
/// parcel quota, weapon tier, speed and time.
struct HUDView: View {
    let state: RaceState
    let mode: GameMode
    let onPrimary: () -> Void
    let onPause: () -> Void

    var body: some View {
        ZStack {
            VStack {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(mode.title.uppercased())
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(0.8))
                        HStack(spacing: 6) {
                            if let icon = UIImage(named: "parcel") {
                                Image(uiImage: icon)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 26)
                            }
                            Text("\(state.parcels)\(state.quota > 0 ? " / \(state.quota)" : "")")
                                .font(.system(size: 20, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color(hex: "#FFD24C"))
                        }
                        WeaponPips(level: state.weaponLevel, max: state.maxWeaponLevel)
                        Text(String(format: "%.0f km/h", state.speed / 40))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 8) {
                        Button(action: onPause) {
                            Image(systemName: state.phase == .paused ? "play.fill" : "pause.fill")
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 40, height: 40)
                                .background(.white.opacity(0.15))
                                .foregroundStyle(.white)
                                .clipShape(Circle())
                        }
                        Text(String(format: "%.1fs", state.elapsed))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                        PostalMeter(fraction: state.meterFraction, invincible: state.invincible)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)

                Spacer()

                RouteProgress(progress: state.progress)

                if state.phase == .ready {
                    VStack(spacing: 8) {
                        Text("DRAG to steer · HOLD to shoot")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                        Button(action: onPrimary) {
                            Text("TAP TO START")
                                .font(.system(size: 20, weight: .heavy, design: .rounded))
                                .padding(.horizontal, 28)
                                .padding(.vertical, 12)
                                .background(Color(hex: "#3A6BFF"))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state.phase)
    }
}

/// Vertical postal meter drawn with the original damage-gauge texture.
private struct PostalMeter: View {
    let fraction: Double
    let invincible: Bool

    var body: some View {
        ZStack {
            if let art = UIImage(named: "meter") {
                Image(uiImage: art)
                    .resizable()
                    .scaledToFit()
                    .opacity(0.28)
                Image(uiImage: art)
                    .resizable()
                    .scaledToFit()
                    .mask {
                        GeometryReader { g in
                            VStack(spacing: 0) {
                                Spacer(minLength: 0)
                                Rectangle().frame(height: g.size.height * clamped)
                            }
                        }
                    }
                    .overlay {
                        if invincible {
                            Rectangle().fill(Color(hex: "#7AC8FF").opacity(0.45))
                        }
                    }
            } else {
                Capsule().fill(.white.opacity(0.2))
            }
        }
        .frame(width: 30, height: 168)
        .overlay(alignment: .top) {
            Text("POSTAL")
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .offset(y: -12)
        }
    }

    private var clamped: Double { min(1, max(0, fraction)) }
}

private struct WeaponPips: View {
    let level: Int
    let max: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i < level ? Color(hex: "#7AC8FF") : Color.white.opacity(0.2))
                    .frame(width: 18, height: 6)
            }
        }
    }
}

private struct RouteProgress: View {
    let progress: Double

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(.black.opacity(0.35))
            Capsule().fill(
                LinearGradient(colors: [Color(hex: "#FFD24C"), Color(hex: "#FF8A3D")],
                               startPoint: .leading, endPoint: .trailing)
            )
            .frame(width: max(4, 300 * progress))
        }
        .frame(width: 300, height: 8)
        .overlay(Capsule().stroke(.white.opacity(0.4), lineWidth: 1))
        .padding(.bottom, 14)
    }
}
