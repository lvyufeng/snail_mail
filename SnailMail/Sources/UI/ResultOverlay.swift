import SwiftUI

struct ResultOverlay: View {
    let won: Bool
    let state: RaceState
    let onReplay: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(spacing: 18) {
                Text(won ? "MAIL DELIVERED!" : "GONE POSTAL")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundStyle(won ? Color(hex: "#4CE07A") : Color(hex: "#FF5A5A"))

                VStack(spacing: 6) {
                    StatRow(label: "Parcels", value: state.quota > 0 ? "\(state.parcels) / \(state.quota)" : "\(state.parcels)")
                    StatRow(label: "Score", value: "\(state.score)")
                    StatRow(label: "Time", value: String(format: "%.1fs", state.elapsed))
                }
                .padding(16)
                .background(.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                HStack(spacing: 14) {
                    Button(action: onReplay) {
                        Label("Replay", systemImage: "arrow.clockwise")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .background(Color(hex: "#3A6BFF"))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }

                    Button { dismiss() } label: {
                        Label("Menu", systemImage: "house.fill")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .background(.white.opacity(0.15))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(30)
        }
    }
}

private struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.white.opacity(0.7))
            Spacer(minLength: 40)
            Text(value).fontWeight(.bold).foregroundStyle(.white)
        }
        .font(.system(size: 16, design: .rounded))
    }
}
