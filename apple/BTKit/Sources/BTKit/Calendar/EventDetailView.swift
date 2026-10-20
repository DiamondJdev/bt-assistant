import EventKit
import SwiftUI

/// Opens the details popover when an event block or chip is clicked.
struct EventDetailsOnTap: ViewModifier {
    let module: CalendarModule
    let item: CalendarEventItem
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture { isPresented = true }
            .popover(isPresented: $isPresented, arrowEdge: .trailing) {
                EventDetailView(module: module, item: item) { isPresented = false }
            }
    }
}

extension View {
    func eventDetailsOnTap(_ item: CalendarEventItem, module: CalendarModule) -> some View {
        modifier(EventDetailsOnTap(module: module, item: item))
    }
}

struct EventDetailView: View {
    let module: CalendarModule
    let item: CalendarEventItem
    let close: () -> Void

    @State private var askSpan = false
    @State private var errorMessage: String?

    var body: some View {
        let event = module.store.event(for: item)
        VStack(alignment: .leading, spacing: 8) {
            Text(item.title).font(.headline)
            Text(timeText).foregroundStyle(.secondary)
            Label {
                Text(item.calendarTitle)
            } icon: {
                Circle().fill(Color(hex: item.colorHex)).frame(width: 8, height: 8)
            }
            if let location = item.location {
                Label(location, systemImage: "mappin.and.ellipse")
            }
            if let event, event.hasRecurrenceRules {
                Label(recurrenceOption(from: event.recurrenceRules).label, systemImage: "repeat")
            }
            if let notes = event?.notes, !notes.isEmpty {
                Text(notes).font(.callout).lineLimit(8)
            }
            Divider()
            if item.isEditable, let event {
                HStack {
                    Button("Edit") {
                        module.editorRequest = EditorRequest(event: event, isNew: false)
                        close()
                    }
                    Button("Delete", role: .destructive) {
                        if item.isRecurring { askSpan = true } else { delete(event, span: .thisEvent) }
                    }
                }
            } else {
                Text("Read-only (subscribed calendar)").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 280, alignment: .leading)
        .spanDialog("Delete this repeating event?", isPresented: $askSpan, verb: "Delete") { span in
            if let event { delete(event, span: span) }
        }
        .errorAlert($errorMessage)
    }

    private var timeText: String {
        if item.isAllDay {
            return (item.start..<max(item.end, item.start)).formatted(.interval.month().day())
        }
        return (item.start..<item.end).formatted(.interval.weekday().month().day().hour().minute())
    }

    private func delete(_ event: EKEvent, span: EditSpan) {
        do {
            try module.store.delete(event, span: span)
            close()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension View {
    /// "This Event Only" / "All Future Events" for edits and deletes of repeating events.
    func spanDialog(_ title: String, isPresented: Binding<Bool>, verb: String, action: @escaping (EditSpan) -> Void) -> some View {
        confirmationDialog(title, isPresented: isPresented) {
            Button("\(verb) This Event Only") { action(.thisEvent) }
            Button("\(verb) All Future Events") { action(.futureEvents) }
            Button("Cancel", role: .cancel) {}
        }
    }

    func errorAlert(_ message: Binding<String?>) -> some View {
        alert(
            "Calendar Error",
            isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
