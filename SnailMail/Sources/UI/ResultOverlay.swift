import SwiftUI

struct ResultOverlay: View {
    let won: Bool
    let state: RaceState
    let onReplay: () -> Void
    let onMenu: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            NeonPanel(border: won ? Palette.good : Palette.danger) {
                VStack(spacing: 18) {
                    Text(headline)
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(won ? Palette.good : Palette.danger)
                        .multilineTextAlignment(.center)
                        .shadow(color: (won ? Palette.good : Palette.danger).opacity(0.6), radius: 10)

                    VStack(spacing: 6) {
                        // The original prints its six tallies as shares of the
                        // run's total, in this order and with these labels, so
                        // the remake keeps the same breakdown.
                        StatRow(label: "Garbage", value: percent(state.sheet.garbage))
                        StatRow(label: "Slug", value: percent(state.sheet.slug))
                        StatRow(label: "Ring", value: percent(state.sheet.ring))
                        StatRow(label: "Parcel Collect", value: percent(state.sheet.parcelCollect))
                        StatRow(label: "Parcel Deliver", value: percent(state.sheet.parcelDeliver))
                        StatRow(label: "Bonus", value: percent(state.sheet.bonus))

                        Rectangle()
                            .fill(Palette.ink.opacity(0.18))
                            .frame(height: 1)
                            .padding(.vertical, 2)

                        StatRow(label: "Parcels",
                                value: state.quota > 0 ? "\(state.delivered) / \(state.quota)" : "\(state.parcels)")
                        StatRow(label: "Score Stats", value: "\(state.score)")
                        StatRow(label: "Time", value: String(format: "%.1fs", state.elapsed))
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black.opacity(0.35))
                    )

                    HStack(spacing: 14) {
                        ArcadeButton(title: "REPLAY", tint: Palette.good, icon: "↻", action: onReplay)
                        ArcadeButton(title: "MENU", tint: Palette.cyan, icon: "⌂", action: onMenu)
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private var headline: String {
        if !won { return "GONE POSTAL" }
        return state.perfect ? "PERFECT SCORE!" : "LEVEL COMPLETE!"
    }

    /// One tally as a whole-number share of the run's total score — the
    /// `Bonus :%i%%` columns the original's results screen shows.
    private func percent(_ value: Int) -> String {
        guard state.score > 0 else { return "0%" }
        return "\(value * 100 / state.score)%"
    }
}

private struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            StatLabel(text: label)
            Spacer(minLength: 40)
            Text(value)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.ink)
        }
    }
}
