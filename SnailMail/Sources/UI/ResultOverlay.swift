import SwiftUI

struct ResultOverlay: View {
    let won: Bool
    let state: RaceState
    let onReplay: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            NeonPanel(border: won ? Palette.good : Palette.danger) {
                VStack(spacing: 18) {
                    Text(won ? "MAIL DELIVERED!" : "GONE POSTAL")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(won ? Palette.good : Palette.danger)
                        .multilineTextAlignment(.center)
                        .shadow(color: (won ? Palette.good : Palette.danger).opacity(0.6), radius: 10)

                    VStack(spacing: 8) {
                        StatRow(label: "Parcels",
                                value: state.quota > 0 ? "\(state.parcels) / \(state.quota)" : "\(state.parcels)")
                        StatRow(label: "Score", value: "\(state.score)")
                        StatRow(label: "Time", value: String(format: "%.1fs", state.elapsed))
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black.opacity(0.35))
                    )

                    HStack(spacing: 14) {
                        ArcadeButton(title: "REPLAY", tint: Palette.good, icon: "↻", action: onReplay)
                        ArcadeButton(title: "MENU", tint: Palette.cyan, icon: "⌂") { dismiss() }
                    }
                }
            }
            .padding(.horizontal, 24)
        }
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
