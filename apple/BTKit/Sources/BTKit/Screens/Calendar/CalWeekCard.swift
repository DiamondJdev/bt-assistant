import SwiftUI

struct CalWeekCard: View {
    @Bindable var store: AppStore
    let now: Date
    @Binding var showsUpcoming: Bool
    let onPick: (CalendarEvent) -> Void

    private var calendar: Calendar { store.calendar }
    private var selected: CalendarEvent? {
        store.events.first { $0.id == store.selectedEventID }
            ?? store.allDayEvents.first { $0.id == store.selectedEventID }
    }
    private var upcoming: [CalendarEvent] {
        CalWeekLayout.upcoming(store.events, week: store.calendarDate, now: now, calendar: calendar)
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            content.fixedSize(horizontal: false, vertical: true)
            ScrollView(.vertical) { content }
        }
        .background(Color.btPaper)
        .overlay(Rectangle().strokeBorder(Color.btInk, lineWidth: 1))
        .background { Rectangle().fill(Color.btInk.opacity(0.12)).offset(x: 8, y: 8) }
        .foregroundStyle(Color.btInk)
    }

    @ViewBuilder private var content: some View {
        if let selected { details(selected) }
        else if showsUpcoming { upcomingList }
        else { nextEvent }
    }

    private var nextEvent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Circle().fill(Color.btAccent).frame(width: 7, height: 7)
                    label(upcoming.first.map { "NEXT · " + CalWeekLayout.countdown(to: $0.start, now: now, calendar: calendar) } ?? "NEXT", color: .btAccentText)
                }
                Spacer(minLength: 4)
                textButton("UP NEXT ↑") { showsUpcoming = true }
            }
            if let event = upcoming.first {
                Button { onPick(event) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(event.title).font(.inter(18, .semibold)).multilineTextAlignment(.leading)
                        Text(dayName(event.start) + " · " + CalWeekLayout.range(event, calendar: calendar))
                            .font(.mono(12)).multilineTextAlignment(.leading)
                        Text(location(event)).font(.inter(12)).foregroundStyle(Color.btMuted)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
            } else {
                Text("Nothing else this week").font(.inter(18, .medium))
            }
        }.padding(20)
    }

    private var upcomingList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                label("UP NEXT")
                Spacer()
                textButton("CLOSE ↓") { showsUpcoming = false }
            }.padding(.bottom, 16)
            if upcoming.isEmpty {
                Text("Nothing else this week").font(.inter(18, .medium)).padding(.bottom, 4)
            }
            ForEach(Array(upcoming.enumerated()), id: \.element.id) { index, event in
                if index == 0 || !calendar.isDate(upcoming[index - 1].start, inSameDayAs: event.start) {
                    label(dayHeading(event.start), color: calendar.isDate(event.start, inSameDayAs: now) ? .btAccentText : .btMuted)
                        .padding(.top, index == 0 ? 0 : 18).padding(.bottom, 8)
                }
                Button { onPick(event) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(CalWeekLayout.time(event.start, calendar: calendar))
                            Text(calendar.component(.hour, from: event.start) < 12 ? "AM" : "PM").foregroundStyle(Color.btMuted)
                        }.font(.mono(11)).frame(width: 64, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.title).font(.inter(14, .semibold)).lineLimit(1)
                            Text(location(event)).font(.inter(12)).foregroundStyle(Color.btMuted)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.multilineTextAlignment(.leading).padding(.vertical, 12).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Rectangle().fill(Color.btRule).frame(height: 1)
            }
        }.padding(20)
    }

    private func details(_ event: CalendarEvent) -> some View {
        let conflicts = event.isAllDay ? [] : CalWeekLayout.conflicts(for: event, in: store.events)
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                label(CalWeekKind.classify(event).label)
                Spacer(minLength: 4)
                textButton("CLOSE") { store.selectedEventID = nil; showsUpcoming = false }
            }
            Text(event.title).font(.inter(20, .semibold)).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 12) {
                detailRow("When", value: CalFormat.string(event.start, "EEEE, MMM d", calendar) + "\n" + (event.isAllDay ? "All day" : CalWeekLayout.range(event, calendar: calendar)))
                detailRow("Where", value: location(event))
                detailRow("Repeats", value: event.recurrenceSummary ?? "Does not repeat")
                detailRow("Conflicts", value: conflicts.isEmpty ? "None" : conflicts.map(\.title).joined(separator: ", "),
                          color: conflicts.isEmpty ? .btInk : .btAccentDeep)
            }
            HStack(spacing: 8) {
                Button("Edit") { store.calSelect(event.id) }.buttonStyle(.pill(.primary, size: .small))
                    .disabled(!CalEventDraft(event: event, isNew: false).isEditable)
                if !event.isAllDay && event.kind != .deadline && event.end > event.start {
                    Button("Start focus") { store.startFocus(from: event) }.buttonStyle(.pill(.secondary, size: .small))
                }
            }
            if !conflicts.isEmpty {
                Button("Ask BT to resolve") {
                    guard store.btIsLive else { return }
                    store.sendToBT(CalWeekLayout.conflictPrompt(for: event, conflicts: conflicts, calendar: calendar))
                    store.route = .bt
                }
                .buttonStyle(.pill(.cta, size: .small)).disabled(!store.btIsLive)
                .help(store.btIsLive ? "Send these overlapping events to BT" : "Connect BT in Settings to resolve conflicts")
            }
        }.padding(20)
    }

    private func detailRow(_ title: String, value: String, color: Color = .btInk) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title).font(.inter(12)).foregroundStyle(Color.btMuted).frame(width: 58, alignment: .leading)
            Text(value).font(.inter(13)).foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func label(_ title: String, color: Color = .btMuted) -> some View {
        Text(title).font(.mono(10)).tracking(0.7).foregroundStyle(color)
    }

    private func textButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.mono(10)).tracking(0.4).padding(.horizontal, 10).padding(.vertical, 6)
                .contentShape(Capsule()).overlay(Capsule().strokeBorder(Color.btLine, lineWidth: 1))
        }
            .buttonStyle(.plain)
    }

    private func location(_ event: CalendarEvent) -> String {
        guard let location = event.location, !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "No location" }
        return location
    }

    private func dayName(_ date: Date) -> String {
        calendar.isDate(date, inSameDayAs: now) ? "Today" : CalFormat.string(date, "EEEE", calendar)
    }

    private func dayHeading(_ date: Date) -> String {
        (calendar.isDate(date, inSameDayAs: now) ? "TODAY · " : "") + CalFormat.string(date, "EEEE d", calendar).uppercased()
    }
}
