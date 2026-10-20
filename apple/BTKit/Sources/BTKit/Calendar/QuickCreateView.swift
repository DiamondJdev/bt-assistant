import EventKit
import SwiftUI

struct QuickCreateView: View {
    let module: CalendarModule
    let close: () -> Void

    @State private var title = ""
    @State private var start: Date
    @State private var minutes = 30
    @State private var calendarID: String
    @State private var errorMessage: String?

    private static let durations = [15, 30, 45, 60, 90, 120]

    init(module: CalendarModule, start: Date, close: @escaping () -> Void) {
        self.module = module
        self.close = close
        _start = State(initialValue: start)
        _calendarID = State(initialValue: module.store.defaultCalendar?.calendarIdentifier ?? "")
    }

    var body: some View {
        let calendars = module.store.writableCalendars()
        Form {
            TextField("Title", text: $title, prompt: Text("New Event"))
                .onSubmit(save)
            DatePicker("Starts", selection: $start)
            Picker("Duration", selection: $minutes) {
                ForEach(Self.durations, id: \.self) { Text(formattedDuration(Double($0 * 60))).tag($0) }
            }
            CalendarPicker(calendars: calendars, selection: $calendarID)
            HStack {
                Button("More Options…") {
                    module.editorRequest = EditorRequest(event: makeEvent(), isNew: true)
                    close()
                }
                Spacer()
                Button("Add", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(calendars.isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
        .errorAlert($errorMessage)
    }

    private func makeEvent() -> EKEvent {
        let event = module.store.newEvent()
        event.title = title.isEmpty ? "New Event" : title
        event.startDate = start
        event.endDate = start.addingTimeInterval(Double(minutes * 60))
        event.calendar = module.store.writableCalendars().first { $0.calendarIdentifier == calendarID }
            ?? module.store.defaultCalendar
        return event
    }

    private func save() {
        do {
            try module.store.save(makeEvent(), span: .thisEvent)
            close()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct CalendarPicker: View {
    let calendars: [EKCalendar]
    @Binding var selection: String

    var body: some View {
        Picker("Calendar", selection: $selection) {
            ForEach(calendars, id: \.calendarIdentifier) { calendar in
                Label {
                    Text(calendar.title)
                } icon: {
                    Image(systemName: "circle.fill").foregroundStyle(Color(cgColor: calendar.cgColor))
                }
                .tag(calendar.calendarIdentifier)
            }
        }
    }
}
