import SwiftUI
#if os(macOS)
import AppKit
#endif

struct CalendarView: View {
    @Bindable var module: CalendarModule
    @Environment(\.openURL) private var openURL
    @State private var showQuickCreate = false

    var body: some View {
        Group {
            switch module.store.access {
            case .notDetermined:
                ContentUnavailableView {
                    Label("Calendar", systemImage: "calendar")
                } description: {
                    Text("BT needs access to your calendars to show your schedule and add events.")
                } actions: {
                    Button("Allow Calendar Access") {
                        Task { await module.store.requestAccess() }
                    }
                }
            case .denied:
                ContentUnavailableView {
                    Label("Calendar Access Is Off", systemImage: "calendar.badge.exclamationmark")
                } description: {
                    Text("Turn on BT under Privacy & Security › Calendars in System Settings, with Full Access.")
                } actions: {
                    #if os(macOS)
                    Button("Open System Settings") {
                        openURL(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                    }
                    #endif
                }
            case .granted:
                calendarBody
            }
        }
        .onAppear { module.store.refreshAccess() }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            module.store.refreshAccess()
        }
        #endif
    }

    private var calendarBody: some View {
        let events = module.visibleEvents()
        return VStack(alignment: .leading, spacing: 0) {
            Text(headerTitle)
                .font(.title2.weight(.semibold))
                .padding(.horizontal)
                .padding(.vertical, 8)
            Divider()
            switch module.mode {
            case .day: DayView(module: module, events: events)
            case .week: WeekView(module: module, events: events)
            case .month: MonthView(module: module, events: events)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Picker("View", selection: $module.mode) {
                    Text("Day").tag(CalendarViewMode.day)
                    Text("Week").tag(CalendarViewMode.week)
                    Text("Month").tag(CalendarViewMode.month)
                }
                .pickerStyle(.segmented)
                Button("Previous", systemImage: "chevron.left") { step(forward: false) }
                Button("Today") { module.focusDate = module.now() }
                Button("Next", systemImage: "chevron.right") { step(forward: true) }
                Button("New Event", systemImage: "plus") { showQuickCreate = true }
                    .popover(isPresented: $showQuickCreate) {
                        QuickCreateView(
                            module: module,
                            start: defaultNewEventStart(on: module.focusDate, now: module.now(), calendar: .current)
                        ) { showQuickCreate = false }
                    }
                #if DEBUG
                Button("Recurring Check", systemImage: "ladybug") { module.store.runRecurringEditCheck() }
                #endif
            }
        }
        .sheet(item: $module.editorRequest) { request in
            EventEditor(module: module, request: request)
        }
        #if DEBUG
        .task {
            if ProcessInfo.processInfo.arguments.contains("-BTRecurringCheck") {
                module.store.runRecurringEditCheck()
            }
        }
        #endif
    }

    private func step(forward: Bool) {
        module.focusDate = stepped(module.focusDate, by: module.mode, forward: forward, calendar: .current)
    }

    private var headerTitle: String {
        let date = module.focusDate
        switch module.mode {
        case .day:
            return date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        case .week:
            let interval = visibleInterval(for: .week, containing: date, calendar: .current)
            return (interval.start..<interval.end.addingTimeInterval(-1))
                .formatted(.interval.month(.abbreviated).day().year())
        case .month:
            return date.formatted(.dateTime.month(.wide).year())
        }
    }
}
