import SwiftUI

/// Month column 4: the selected day, study this month, and BT's look-ahead.
struct CalMonthPanel: View {
    @Bindable var store: AppStore

    private var cal: Calendar { store.calendar }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            selectedDay
            study
            Spacer(minLength: 0)
            lookAhead
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var selectedDay: some View {
        let day = store.calendarDate
        let isToday = cal.isDate(day, inSameDayAs: store.now)
        let items = CalLayers.visible(store.events(on: day), showing: store.calendarScreen.monthLayers)
        let timed = items.filter { $0.kind != .deadline }
        let dues = items.filter { $0.kind == .deadline }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(CalFormat.string(day, "EEE d", cal) + (isToday ? " · today" : "")).monoLabel()
                Spacer()
                Button(isToday ? "Open day →" : "Open week →") {
                    store.calendarMode = isToday ? .day : .week
                }
                .buttonStyle(.monoLink)
            }
            VStack(alignment: .leading, spacing: 0) {
                if items.isEmpty {
                    Text("Nothing on this day with the current layers.").foregroundStyle(Color.btMuted).padding(.vertical, 8)
                }
                ForEach(timed) { e in
                    itemRow(e, text: "\(CalFormat.time(e.start, cal))  \(CalMonthMath.itemTitle(e))", accent: false)
                }
                ForEach(dues) { e in
                    itemRow(e, text: "\(e.title) due · \(CalFormat.time(e.start, cal))", accent: true)
                }
            }
        }
    }

    private func itemRow(_ e: CalendarEvent, text: String, accent: Bool) -> some View {
        HStack(spacing: 10) {
            CalSwatch(kind: e.kind, size: 9).frame(width: 16, alignment: .leading)
            Text(text).font(.inter(14, accent ? .semibold : .medium))
                .foregroundStyle(accent ? Color.btAccentDeep : .btInk).lineLimit(1)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.btRule).frame(height: 1) }
    }

    private var study: some View {
        let s = CalMonthMath.study(month: store.calendarDate, now: store.now, events: store.events, cal: cal)
        let t = CalMonthMath.ticks(logged: s.logged, booked: s.booked)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Study this month").monoLabel()
                Spacer()
                Text("Goal \(Int(CalMonthMath.studyGoalHours))h").monoLabel()
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(CalFormat.hours(s.logged)).interStyle(52, .medium, tracking: -0.045)
                Text("logged · \(CalFormat.hours(s.booked)) booked ahead").foregroundStyle(Color.btMuted)
            }
            TickBar(count: CalMonthMath.tickCount, filled: t.filled, dashed: t.dashed)
                .accessibilityLabel("\(CalFormat.hours(s.logged)) logged, \(CalFormat.hours(s.booked)) booked, of \(Int(CalMonthMath.studyGoalHours))h")
        }
        .padding(.top, 20)
        .overlay(alignment: .top) {
            DashedEdges(right: false, bottom: false, top: true).stroke(Color.btLine, style: StrokeStyle(lineWidth: 1, dash: BTMetrics.dash))
        }
    }

    private var lookAhead: some View {
        let drafted = !store.calendarScreen.monthDraftIDs.isEmpty
        let monday = CalMonthMath.nextWeekStart(now: store.now, cal: cal)
        let span = CalFormat.span(monday, cal.date(byAdding: .day, value: 4, to: monday)!, cal, separator: "–")
        let counts = CalMonthMath.nextWeekCounts(now: store.now, events: store.events, cal: cal)
        return VStack(alignment: .leading, spacing: 12) {
            Text("BT · looking ahead").monoLabel(10, color: .btAccentDeep)
            Group {
                if drafted {
                    Text("Drafted \(store.calendarScreen.monthDraftIDs.count) blocks for \(span). ")
                        + Text("They’re dashed orange until you keep them.").foregroundStyle(Color.btAccentDeep)
                } else {
                    Text("\(span) has \(plural(counts.deadlines, "deadline")) and \(plural(counts.study, "study block")). ")
                        + Text("I can draft 4 more around your shifts.").foregroundStyle(Color.btAccentDeep)
                }
            }
            .interStyle(19, .medium, tracking: -0.015)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if drafted {
                    Button("Review in Week") { store.open(.calendar(.week, date: monday)) }.buttonStyle(.pill(.primary))
                    Button { store.calUndoLookAhead() } label: {
                        Text("Undo").font(.inter(13)).underline().padding(.horizontal, 8).frame(minHeight: 36).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Button("Draft blocks") { store.calDraftLookAhead() }.buttonStyle(.pill(.primary))
                    Button("Show me first") {
                        store.calDraftLookAhead()
                        if let first = store.calendarScreen.monthDraftIDs.first.flatMap(store.event) { store.calendarDate = first.start }
                    }
                    .buttonStyle(.pill(.secondary))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.btAccent.opacity(0.06))
        .overlay(Rectangle().strokeBorder(Color.btAccent, style: StrokeStyle(lineWidth: 1.5, dash: BTMetrics.dash)))
    }

    private func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
}
