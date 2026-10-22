import SwiftUI

/// Day columns 1–2: the agenda. Study blocks edit inline; NOW links to Focus.
struct CalDayAgenda: View {
    @Bindable var store: AppStore

    private var cal: Calendar { store.calendar }

    var body: some View {
        let rows = CalDayRow.rows(day: store.calendarDate, now: store.now, events: store.events, cal: cal)
        // Plain stack when it fits, scrolling only when the day overflows.
        ViewThatFits(in: .vertical) {
            list(rows).frame(maxHeight: .infinity, alignment: .top)
            ScrollView { list(rows) }.scrollIndicators(.never)
        }
    }

    private func list(_ rows: [CalDayRow]) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                if rows.isEmpty {
                    Text("Nothing on this day.").font(.inter(17)).foregroundStyle(Color.btMuted).padding(.vertical, 12)
                }
                ForEach(rows) { row in
                    switch row {
                    case let .event(e, isPast):
                        if Self.isEditable(e), store.selectedEventID == e.id {
                            CalDayEditRow(store: store, event: e)
                        } else {
                            eventRow(e, isPast: isPast)
                        }
                    case .now: nowRow
                    case let .gap(start, hours): gapRow(start: start, hours: hours)
                    case let .due(e): dueRow(e)
                    }
                }
            }
            .padding(EdgeInsets(top: 8, leading: 20, bottom: 20, trailing: 20))
    }

    static func isEditable(_ e: CalendarEvent) -> Bool { e.kind == .studyPlanned || e.kind == .btDraft }

    private func row<Middle: View, Trailing: View>(
        time: String, timeColor: Color = .btMuted, alignment: VerticalAlignment = .firstTextBaseline,
        @ViewBuilder middle: () -> Middle, @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: alignment, spacing: 16) {
            Text(time).font(.mono(12)).foregroundStyle(timeColor).frame(width: 64, alignment: .leading)
            middle().frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
    }

    private func eventRow(_ e: CalendarEvent, isPast: Bool) -> some View {
        let editable = Self.isEditable(e)
        let content = row(time: CalFormat.time(e.start, cal)) {
            Text(e.title)
                .font(.inter(17, editable ? .semibold : isPast ? .regular : .medium))
                .foregroundStyle(e.kind == .btDraft ? Color.btAccentDeep : isPast ? .btMuted : .btInk)
                .lineLimit(1)
        } trailing: {
            Text(CalFormat.sourceLabel(e)).font(.mono(10)).tracking(0.6).foregroundStyle(Color.btMuted)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.btRule).frame(height: 1) }
        .contentShape(Rectangle())
        return Group {
            if editable {
                Button { store.selectedEventID = e.id } label: { content }
                    .buttonStyle(.plain)
                    .accessibilityHint("Edit block")
            } else {
                content
            }
        }
    }

    private var nowRow: some View {
        let f = store.focus
        let title = f.mode == .focus ? "Focus · \(f.taskTitle)" : "Break · back to \(f.taskTitle)"
        return Button { store.open(.focus) } label: {
            row(time: "NOW", timeColor: Color(hex: 0xF0A27F), alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.inter(19, .medium)).lineLimit(1)
                    Text("Logging to calendar as you go · session \(f.number) of \(f.plannedCount)")
                        .font(.inter(12)).foregroundStyle(Color.btTrack)
                }
            } trailing: {
                Text("Open →").font(.mono(18))
            }
            .foregroundStyle(Color.btInkOnDark)
            .padding(.vertical, 14)
            .padding(.horizontal, 12)
            .background(Color.btInk)
            .padding(.horizontal, -12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Now: \(title). Open Focus")
    }

    private func gapRow(start: Date, hours: Double) -> some View {
        row(time: CalFormat.time(start, cal), alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Open · \(CalFormat.hours((hours * 4).rounded(.down) / 4)) until bed")
                    .font(.inter(17)).foregroundStyle(Color.btMuted)
                CalHatch(spacing: 6, lineWidth: 2).frame(height: 6)
            }
        } trailing: {
            Button("+ Fill with study") { store.calFillGap(at: start) }.buttonStyle(.pill(.secondary, size: .small))
        }
        .padding(.vertical, 18)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.btRule).frame(height: 1) }
    }

    private func dueRow(_ e: CalendarEvent) -> some View {
        row(time: CalFormat.time(e.start, cal), timeColor: .btAccentText) {
            Text("\(e.title) due").font(.inter(17, .semibold)).foregroundStyle(Color.btAccentDeep)
        } trailing: {
            Text(CalFormat.sourceLabel(e).components(separatedBy: " · ").first ?? "").font(.mono(10)).tracking(0.6).foregroundStyle(Color.btMuted)
        }
        .padding(.vertical, 12)
    }
}

/// Inline editor for a study block: title, −15/+15, Run as Focus, Save, Delete.
struct CalDayEditRow: View {
    @Bindable var store: AppStore
    let event: CalendarEvent

    var body: some View {
        let cal = store.calendar
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(CalFormat.time(event.start, cal)).font(.mono(12)).foregroundStyle(Color.btMuted).frame(width: 64, alignment: .leading)
                TextField("Title", text: Binding(get: { store.event(event.id)?.title ?? event.title }, set: { store.calSetTitle(event.id, $0) }))
                    .textFieldStyle(.plain)
                    .font(.inter(19, .medium))
                    .padding(.vertical, 2)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.btInk).frame(height: 1.5) }
                Text(CalFormat.sourceLabel(event)).font(.mono(10)).tracking(0.6).foregroundStyle(Color.btMuted)
            }
            HStack(spacing: 8) {
                HStack(spacing: 0) {
                    step("−15", minutes: -15)
                    Text(CalFormat.range(event.start, event.end, cal, separator: " – "))
                        .font(.mono(12)).padding(.horizontal, 12)
                    step("+15", minutes: 15)
                }
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Color.btInk, lineWidth: 1))
                Toggle(isOn: Binding(get: { store.event(event.id)?.runAsFocus ?? false }, set: { store.calSetRunAsFocus(event.id, $0) })) {
                    Text("Run as Focus").font(.inter(13))
                }
                .toggleStyle(CalCheckboxStyle(accent: true, size: 16))
                Spacer(minLength: 0)
                Button("Save") { store.selectedEventID = nil }.buttonStyle(.pill(.primary, size: .small))
                Button { store.deleteEvent(event.id) } label: {
                    Text("Delete").font(.inter(12)).underline().foregroundStyle(Color.btAccentDeep).padding(.horizontal, 6).frame(minHeight: 32)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 80)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .background(Color.btPaper)
        .overlay(Rectangle().strokeBorder(Color.btInk, style: StrokeStyle(lineWidth: 1.5, dash: BTMetrics.dash)))
        .padding(.horizontal, -12)
        .padding(.vertical, 6)
    }

    private func step(_ label: String, minutes: Int) -> some View {
        Button { store.calNudge(event.id, minutes: minutes) } label: {
            Text(label).font(.inter(12)).padding(.horizontal, 12).frame(height: 32).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: minutes < 0 ? .trailing : .leading) { Rectangle().fill(Color.btInk).frame(width: 1) }
        .accessibilityLabel(minutes < 0 ? "15 minutes earlier" : "15 minutes later")
    }
}

/// Vertical hatch lines, used for open time.
struct CalHatch: View {
    var spacing: CGFloat = 5
    var lineWidth: CGFloat = 1
    var color: Color = .btLine

    var body: some View {
        Canvas { ctx, size in
            var x: CGFloat = 0
            while x < size.width {
                ctx.fill(Path(CGRect(x: x, y: 0, width: lineWidth, height: size.height)), with: .color(color))
                x += spacing
            }
        }
        .accessibilityHidden(true)
    }
}
