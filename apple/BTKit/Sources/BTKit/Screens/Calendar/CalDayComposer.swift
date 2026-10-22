import SwiftUI

/// Day column 3: "Tell BT what to schedule", BT's drafted card, and Try prompts.
struct CalDayComposer: View {
    @Bindable var store: AppStore

    static let prompts = ["Protect 2h for bt-client every weekday", "Move anything that clashes with my Sat shift"]

    private var state: CalendarScreenState { store.calendarScreen }
    private var cal: Calendar { store.calendar }

    private var draft: CalDayDraft {
        state.dayDraft ?? CalDayDraft.parse(state.nlInput, day: store.calendarDate, now: store.now, events: store.events, cal: cal)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tell BT what to schedule").monoLabel()
            input
            card(draft)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 8) {
                Text("Try").monoLabel()
                ForEach(Self.prompts, id: \.self) { p in
                    Button { store.calendarScreen.nlInput = p } label: {
                        Text(p).font(.inter(13)).lineLimit(1)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                            .overlay(Rectangle().strokeBorder(Color.btLine, lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var input: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("", text: Bindable(store.calendarScreen).nlInput)
                .textFieldStyle(.plain)
                .font(.inter(22))
                .tracking(-0.44)
                .onSubmit(redraft)
                .accessibilityLabel("Tell BT what to schedule")
            Button(action: redraft) {
                Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.btInkOnDark)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.btInk))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Send")
        }
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.btInk).frame(height: 1.5) }
    }

    private func redraft() {
        state.dayDraft = CalDayDraft.parse(state.nlInput, day: store.calendarDate, now: store.now, events: store.events, cal: cal)
        state.dayDraftAddedID = nil
    }

    private func card(_ d: CalDayDraft) -> some View {
        let added = state.dayDraftAddedID.flatMap(store.event) != nil
        return VStack(alignment: .leading, spacing: 12) {
            Text(added ? "Added by BT" : "BT drafted").monoLabel(10, color: .btAccentDeep)
            Text(d.title).interStyle(22, .medium, tracking: -0.02).fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 0, verticalSpacing: 8) {
                detail("When", Text(CalFormat.string(d.start, "EEE", cal) + " " + CalFormat.range(d.start, d.end, cal, separator: " – ")).font(.mono(12)))
                detail("Calendar", Text("Study · Apple"))
                detail("Focus", Text(d.focusText))
                detail("Why", Text(d.why))
            }
            .font(.inter(13))
            if added {
                HStack(spacing: 8) {
                    Text("Added to your day").font(.inter(14, .semibold))
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).accessibilityHidden(true)
                    Button { store.calUndoDayDraft() } label: {
                        Text("Undo").font(.inter(13)).underline().padding(.horizontal, 8).frame(minHeight: 32).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack(spacing: 8) {
                    Button("Add to calendar") { store.calAddDayDraft(d) }.buttonStyle(.pill(.cta))
                    Button("Edit details") { store.calAddDayDraft(d, edit: true) }.buttonStyle(.pill(.secondary))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.btAccent.opacity(0.06))
        .overlay(Rectangle().strokeBorder(Color.btAccent, style: StrokeStyle(lineWidth: 1.5, dash: BTMetrics.dash)))
    }

    private func detail(_ label: String, _ value: Text) -> some View {
        GridRow {
            Text(label).foregroundStyle(Color.btMuted).frame(width: 80, alignment: .leading)
            value.frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        }
    }
}
