import EventKit
import SwiftUI

/// Asks `CalendarView` to show the edit sheet for an existing occurrence or a new event.
struct EditorRequest: Identifiable {
    let id = UUID()
    let event: EKEvent
    let isNew: Bool
}

struct EventEditor: View {
    let module: CalendarModule
    let request: EditorRequest
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var isAllDay: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var calendarID: String
    @State private var location: String
    @State private var notes: String
    @State private var recurrence: RecurrenceOption
    @State private var hasRecurrenceEnd: Bool
    @State private var recurrenceEnd: Date
    @State private var askSpan = false
    @State private var errorMessage: String?

    private let originalRecurrence: RecurrenceOption
    private let originalRecurrenceEnd: Date?

    init(module: CalendarModule, request: EditorRequest) {
        self.module = module
        self.request = request
        let event = request.event
        let option = recurrenceOption(from: event.recurrenceRules)
        let ruleEnd = event.recurrenceRules?.first?.recurrenceEnd?.endDate
        originalRecurrence = option
        originalRecurrenceEnd = ruleEnd
        _title = State(initialValue: event.title ?? "")
        _isAllDay = State(initialValue: event.isAllDay)
        _start = State(initialValue: event.startDate)
        _end = State(initialValue: event.endDate)
        _calendarID = State(initialValue: event.calendar?.calendarIdentifier ?? "")
        _location = State(initialValue: event.location ?? "")
        _notes = State(initialValue: event.notes ?? "")
        _recurrence = State(initialValue: option)
        _hasRecurrenceEnd = State(initialValue: ruleEnd != nil)
        _recurrenceEnd = State(initialValue: ruleEnd ?? Calendar.current.date(byAdding: .month, value: 3, to: event.startDate)!)
    }

    var body: some View {
        Form {
            TextField("Title", text: $title)
            Toggle("All-day", isOn: $isAllDay)
            DatePicker("Starts", selection: $start, displayedComponents: isAllDay ? .date : [.date, .hourAndMinute])
            DatePicker("Ends", selection: $end, in: start..., displayedComponents: isAllDay ? .date : [.date, .hourAndMinute])
            CalendarPicker(calendars: module.store.writableCalendars(), selection: $calendarID)
            TextField("Location", text: $location)
            TextField("Notes", text: $notes, axis: .vertical).lineLimit(3...6)
            recurrenceSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 380, minHeight: 440)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if !request.isNew && request.event.hasRecurrenceRules { askSpan = true } else { save(span: .thisEvent) }
                }
                .disabled(end < start)
            }
        }
        .spanDialog("Save changes to this repeating event?", isPresented: $askSpan, verb: "Save", action: save)
        .errorAlert($errorMessage)
    }

    @ViewBuilder private var recurrenceSection: some View {
        if case .custom = recurrence {
            LabeledContent("Repeat", value: "Custom repeat (set in another app)")
        } else {
            Picker("Repeat", selection: $recurrence) {
                ForEach(RecurrenceOption.editable, id: \.self) { Text($0.label).tag($0) }
            }
            if recurrence != .none {
                Toggle("End repeat", isOn: $hasRecurrenceEnd)
                if hasRecurrenceEnd {
                    DatePicker("End repeat on", selection: $recurrenceEnd, in: start..., displayedComponents: .date)
                }
            }
        }
    }

    private func save(span: EditSpan) {
        let event = request.event
        event.title = title.isEmpty ? "New Event" : title
        event.isAllDay = isAllDay
        event.startDate = start
        event.endDate = end
        if let calendar = module.store.writableCalendars().first(where: { $0.calendarIdentifier == calendarID }) {
            event.calendar = calendar
        }
        event.location = location.isEmpty ? nil : location
        event.notes = notes.isEmpty ? nil : notes
        let newEnd = hasRecurrenceEnd ? recurrenceEnd : nil
        // Only touch rules the owner changed, so custom rules and untouched series survive the save.
        if recurrence != originalRecurrence || newEnd != originalRecurrenceEnd,
           let rules = recurrenceRules(for: recurrence, end: newEnd) {
            event.recurrenceRules = rules.isEmpty ? nil : rules
        }
        do {
            try module.store.save(event, span: span)
            dismiss()
        } catch {
            event.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
