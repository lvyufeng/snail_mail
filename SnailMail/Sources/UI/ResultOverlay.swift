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
                            .font(.retail(30, weight: .black))
                            .foregroundStyle(won ? Palette.good : Palette.danger)
                            .multilineTextAlignment(.center)
                            .shadow(color: (won ? Palette.good : Palette.danger).opacity(0.6), radius: 10)
                        ForEach(sublines, id: \.self) { subline in
                            Text(subline)
                                .font(.retail(14, weight: .heavy))
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
                        Text(packageLine)
                            .font(.retail(15, weight: .heavy))
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
                        Text("\(board.title) #\(place)")
                            .font(.retail(13, weight: .heavy))
                            .foregroundStyle(Palette.gold)
                    }

                    HStack(spacing: 14) {
                        ArcadeButton(title: "REPLAY", tint: Palette.good, icon: "↻", action: onReplay)
                        // The original's own label for leaving the results
                        // page; it hands over to the "Thanks For Playing!"
                        // page before the menu, exactly as the retail build
                        // does (`Click to Continue`, 0x4a11c4).
                        ArcadeButton(title: "CONTINUE", tint: Palette.cyan, icon: "▶", action: onMenu)
                    }
                }
            }
            .padding(.horizontal, 24)
        }
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-dumpresults") {
                NSLog("RESULTS headline=<%@> sublines=%@ packages=<%@>",
                      headline, "\(sublines)", packageLine)
            }
        }
        #endif
    }

    private var headline: String {
        if !won { return "GONE POSTAL" }
        // `0x404b5e`: the arcade campaign's win line is the pre-baked
        // "PERFECT SCORE!>50,000 Bonus Points" (0x4a11fc) whatever the postal
        // meter came through at; every other mode prints "LEVEL COMPLETE!>"
        // (0x4a11e8) and has its bonus copied onto the line after it. The
        // remake also keeps the perfect run's line for the other modes, which
        // the original never draws because only the campaign is scored there.
        return (mode == .arcade || state.perfect) ? "PERFECT SCORE!" : "LEVEL COMPLETE!"
    }

    /// The lines the original prints under its headline: `Delivery Complete!`
    /// (0x4a1250) once the whole quota has gone over the counter, then the
    /// completion award — the arcade line's own `50,000 Bonus Points`, or the
    /// `<bonus> Bonus Points` the routine appends at 0x404be8.
    private var sublines: [String] {
        guard won else { return [] }
        var lines: [String] = []
        if state.quota > 0 && state.delivered >= state.quota {
            lines.append("Delivery Complete!")
        }
        if mode == .arcade || state.perfect {
            lines.append("50,000 Bonus Points")
        } else {
            lines.append("\(Self.grouped(state.completionBonus)) Bonus Points")
        }
        return lines
    }

    /// "00 Packages Delivered" / " 0 Package Delivered" (0x4a1220, 0x4a1238):
    /// the count sits in the leading two-character field, plural unless a
    /// single package went over the counter.
    private var packageLine: String {
        let count = String(format: "%2d", state.delivered)
        return "\(count) \(state.delivered == 1 ? "Package" : "Packages") Delivered"
    }

    /// The retail build groups its numbers by thousands with commas — the
    /// append helper at 0x401030 drops one in as its divisor passes 100,000
    /// and 100.
    static func grouped(_ value: Int) -> String {
        let digits = String(abs(value))
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return value < 0 ? "-" + out : out
    }

    private func submit(_ board: HighScores.Board) {
        place = scores.submit(board, name: name, score: state.score, level: levelName)
        submitted = true
        Sound.shared.play(.highlight)
    }

    /// One tally as a whole-number share of the run's total score — the
    /// `Bonus :%i%%` columns the original's results screen shows.
    private func percent(_ value: Int) -> String {
        guard state.score > 0 else { return "0%" }
        return "\(value * 100 / state.score)%"
    }
}

/// The page the retail build shows once the results are dismissed: a
/// `Thanks For Playing!` line (0x4a4a34) over a nudge toward one of the other
/// modes, then one more click to continue.
///
/// The build's own end-of-run routine (`0x433fb0` to build the page,
/// `0x4340d0` to run it) prints both nudges in turn — `Test your reflexes in
/// Challenge Mode!` (0x4a4a6c) and `Improve your skills in Time Trial!`
/// (0x4a4a48) — and finishes on `Click to Continue`. A still page cannot
/// alternate them, so it keeps the one aimed at the mode the run was not in.
struct ThanksOverlay: View {
    let mode: GameMode
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            NeonPanel(border: Palette.gold) {
                VStack(spacing: 18) {
                    Text("THANKS FOR PLAYING!")
                        .font(.retail(26, weight: .black))
                        .foregroundStyle(Palette.gold)
                        .multilineTextAlignment(.center)
                        .shadow(color: Palette.gold.opacity(0.6), radius: 10)

                    Text(nudge)
                        .font(.retail(16, weight: .heavy))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)

                    ArcadeButton(title: "CLICK TO CONTINUE", tint: Palette.good, icon: "▶",
                                 action: onContinue)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    /// The nudge toward the mode the finished run was not played in.
    private var nudge: String {
        mode == .speedRun
            ? "Test your reflexes in Challenge Mode!"
            : "Improve your skills in Time Trial!"
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
                .font(.retail(13, weight: .heavy))
                .foregroundStyle(Palette.gold)
            TextField("Enter your name here!", text: $name)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .multilineTextAlignment(.center)
                .font(.retail(16, weight: .heavy))
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
                .font(.retail(17, weight: .heavy))
                .foregroundStyle(Palette.ink)
        }
    }
}
