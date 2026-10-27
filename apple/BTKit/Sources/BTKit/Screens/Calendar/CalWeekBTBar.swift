import SwiftUI

/// Week's bottom bar: BT's proposal about its draft block, with Keep / Move later / Discard and Undo.
struct CalWeekBTBar: View {
    @Bindable var store: AppStore

    var body: some View {
        let review = store.calendarScreen.draft
        HStack(spacing: 14) {
            Text("BT").monoLabel(color: .btAccentDeep)
            Text(Self.sentence(review.outcome, block: store.calDraftEvent ?? review.before, cal: store.calendar))
                .font(.inter(15, .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if review.outcome == .pending {
                if store.calDraftEvent != nil {
                    Button("Keep it") { store.calKeepDraft() }.buttonStyle(.pill(.primary, size: .small))
                    Button("Move later") { store.calMoveDraftLater() }.buttonStyle(.pill(.secondary, size: .small))
                    underlined("Discard") { store.calDiscardDraft() }
                }
            } else {
                underlined("Undo") { store.calUndoDraft() }
                Button("Ask BT something else") { store.open(.bt()) }.buttonStyle(.pill(.secondary, size: .small))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 58)
        .background(Color.btAccent.opacity(0.06))
        .overlay(Rectangle().strokeBorder(Color.btAccent, style: StrokeStyle(lineWidth: 1, dash: BTMetrics.dash)))
    }

    private func underlined(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.inter(13)).underline().padding(.horizontal, 6).frame(minHeight: 34).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The sentence for each outcome, built from the block as it is now.
    static func sentence(_ outcome: CalDraftReview.Outcome, block: CalendarEvent?, cal: Calendar) -> String {
        guard let block else { return "No drafts waiting. Ask BT to find time for something." }
        let day = CalFormat.string(block.start, "EEEE", cal)
        let range = CalFormat.range(block.start, block.end, cal)
        switch outcome {
        case .pending:
            return "\(day) evening is open after CHEM SI. I drafted \(block.title) \(range) so the lab report isn’t a last-minute scramble."
        case .kept:
            let plan = (block.focusPlan ?? "2×25").replacingOccurrences(of: "×", with: " × ")
            return "Kept. \(block.title) is on \(day) \(range), and Focus will run it as \(plan)."
        case .moved:
            return "Moved to \(range) so you get a real dinner break after SI."
        case .discarded:
            return "Discarded. Want me to look for time tomorrow instead?"
        }
    }
}
