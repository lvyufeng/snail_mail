import SwiftUI

struct ResultOverlay: View {
    let won: Bool
    let state: RaceState
    let mode: GameMode
    let levelName: String
    let onReplay: () -> Void
    let onMenu: () -> Void

    @ObservedObject private var scores = HighScores.shared
    @State private var name = ""
    @State private var submitted = false
    @State private var place: Int?

    /// The score table this run feeds, or nil for the modes the original never
    /// ranked.
    private var board: HighScores.Board? { HighScores.board(for: mode) }

    private var canSubmit: Bool {
        guard won, !submitted, let board else { return false }
        return scores.qualifies(board, score: state.score)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            NeonPanel(border: won ? Palette.good : Palette.danger) {
                VStack(spacing: 18) {
                    VStack(spacing: 4) {
                        Text(headline)
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .foregroundStyle(won ? Palette.good : Palette.danger)
                            .multilineTextAlignment(.center)
                            .shadow(color: (won ? Palette.good : Palette.danger).opacity(0.6), radius: 10)
                        if let subline {
                            Text(subline)
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .tracking(0.5)
                                .foregroundStyle(Palette.gold)
                                .multilineTextAlignment(.center)
                        }
                    }

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

                        // "NN Packages Delivered", singular for a lone package.
                        Text("\(state.delivered) \(state.delivered == 1 ? "Package" : "Packages") Delivered")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(Palette.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        StatRow(label: "Score Stats", value: "\(state.score)")
                        StatRow(label: "Time", value: String(format: "%.1fs", state.elapsed))
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black.opacity(0.35))
                    )

                    if canSubmit, let board {
                        NameEntry(board: board, name: $name) {
                            submit(board)
                        } cancel: {
                            submitted = true
                        }
                    } else if let place, let board {
                        Text("\(board.title) — #\(place)")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(Palette.gold)
                    }

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

    /// The second line the original prints under its headline: the perfect-run
    /// bonus, or the note that the whole quota was handed over.
    private var subline: String? {
        guard won else { return nil }
        if state.perfect { return "50,000 Bonus Points" }
        if state.quota > 0 && state.delivered >= state.quota { return "Delivery Complete!" }
        return nil
    }

    private func submit(_ board: HighScores.Board) {
        place = scores.submit(board, name: name, score: state.score, level: levelName)
        submitted = true
        Sound.shared.play(.upgrade)
    }

    /// One tally as a whole-number share of the run's total score — the
    /// `Bonus :%i%%` columns the original's results screen shows.
    private func percent(_ value: Int) -> String {
        guard state.score > 0 else { return "0%" }
        return "\(value * 100 / state.score)%"
    }
}

/// The original's "Enter your name here!" prompt, shown when a run makes the
/// board.
private struct NameEntry: View {
    let board: HighScores.Board
    @Binding var name: String
    let submit: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("\(board.title)!")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.gold)
            TextField("Enter your name here!", text: $name)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .multilineTextAlignment(.center)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Palette.cyan.opacity(0.7), lineWidth: 1)
                )
                .submitLabel(.done)
                .onSubmit(submit)
            HStack(spacing: 12) {
                ArcadeButton(title: "SUBMIT", tint: Palette.good, action: submit)
                ArcadeButton(title: "CANCEL", tint: Palette.danger, action: cancel)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.35))
        )
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
