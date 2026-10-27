import SwiftUI

struct CalDayAgenda: View {
    @Bindable var store: AppStore
    @State private var showEarlier = false
    @State private var showDeadlines = false
    @State private var showAllDay = false

    private var cal: Calendar { store.calendar }

    var body: some View {
        let sections = CalDaySections(day: store.calendarDate, now: store.now, events: store.calVisibleEvents, cal: cal)
        let allDay = store.allDayEvents(on: store.calendarDate)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !allDay.isEmpty {
                        DisclosureGroup("All day · \(allDay.count)", isExpanded: $showAllDay) {
                            ForEach(allDay) { event in eventRow(event, isPast: false) }
                        }
                    }
                    if !sections.deadlines.isEmpty {
                        DisclosureGroup("Due today · \(sections.deadlines.count)", isExpanded: $showDeadlines) {
                            ForEach(sections.deadlines) { event in eventRow(event, isPast: false) }
                        }
                    }
                    if !sections.earlier.isEmpty {
                        DisclosureGroup("Earlier · \(sections.earlier.count) events", isExpanded: $showEarlier) {
                            ForEach(sections.earlier) { row in agendaRow(row) }
                        }
                    }
                    if sections.upcoming.isEmpty && sections.earlier.isEmpty && allDay.isEmpty && sections.deadlines.isEmpty {
                        Text("Nothing on this day.").font(.inter(17)).foregroundStyle(Color.btMuted)
                    }
                    ForEach(sections.upcoming) { row in agendaRow(row).id(row.id) }
                }
                .font(.inter(13))
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear {
                if cal.isDate(store.calendarDate, inSameDayAs: store.now), let first = sections.upcoming.first {
                    proxy.scrollTo(first.id, anchor: .top)
                }
            }
            .onChange(of: store.calendarDate) { _, _ in
                showEarlier = false
                showDeadlines = false
                showAllDay = false
                if let first = sections.upcoming.first { proxy.scrollTo(first.id, anchor: .top) }
            }
        }
    }

    @ViewBuilder private func agendaRow(_ row: CalDayRow) -> some View {
        switch row {
        case let .event(event, isPast): eventRow(event, isPast: isPast)
        case .now:
            HStack(spacing: 12) {
                Text("NOW · " + CalFormat.string(store.now, "h:mm a", cal)).monoLabel(color: .btAccentDeep)
                Rectangle().fill(Color.btAccent).frame(height: 1)
            }
            .padding(.vertical, 8)
        case let .gap(start, hours):
            HStack(spacing: 12) {
                Text("Open · " + CalFormat.hours(hours)).font(.inter(14)).foregroundStyle(Color.btMuted)
                Spacer()
                Button("+ Plan time") { store.calFillGap(at: start) }
                    .buttonStyle(.pill(.secondary, size: .small))
            }
            .padding(.vertical, 12)
        case let .due(event): eventRow(event, isPast: false)
        }
    }

    private func eventRow(_ event: CalendarEvent, isPast: Bool) -> some View {
        Button { store.calSelect(event.id) } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.isAllDay ? "All day" : CalFormat.string(event.start, "h:mm a", cal))
                    if !event.isAllDay {
                        Text(CalFormat.string(event.end, cal.isDate(event.start, inSameDayAs: event.end) ? "h:mm a" : "EEE h:mm a", cal))
                            .foregroundStyle(Color.btMuted)
                    }
                }
                .font(.mono(12))
                .frame(width: 100, alignment: .leading)
                CalSwatch(kind: event.kind, size: 8)
                Text(event.title).font(.inter(16, .medium)).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if event.runAsFocus {
                    Image(systemName: "timer").foregroundStyle(Color.btMuted)
                        .accessibilityLabel("Scheduled focus")
                }
            }
            .foregroundStyle(isPast ? Color.btMuted : .btInk)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(Color.btRule).frame(height: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Open event details")
    }
}

struct CalHatch: View {
    var spacing: CGFloat = 5
    var lineWidth: CGFloat = 1
    var color: Color = .btLine

    var body: some View {
        Canvas { context, size in
            var position: CGFloat = 0
            while position < size.width {
                context.fill(Path(CGRect(x: position, y: 0, width: lineWidth, height: size.height)), with: .color(color))
                position += spacing
            }
        }
        .accessibilityHidden(true)
    }
}
