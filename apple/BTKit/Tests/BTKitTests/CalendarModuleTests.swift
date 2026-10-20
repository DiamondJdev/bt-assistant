import EventKit
import Testing
@testable import BTKit

@MainActor
struct CalendarModuleTests {
    @Test func declaresCalendarTools() {
        let module = CalendarModule()
        #expect(module.id == "calendar")
        #expect(module.name == "Calendar")
        #expect(module.tools.map(\.name) == [
            "calendar_list_events",
            "calendar_create_event",
            "calendar_update_event",
            "calendar_delete_event",
        ])
        #expect(module.tools.allSatisfy { $0.name.wholeMatch(of: /[a-zA-Z0-9_-]+/) != nil })
    }

    @Test func snapshotNilWithoutAccess() {
        let store = CalendarStore(store: EKEventStore())
        #expect(store.access != .granted)
        let module = CalendarModule(store: store)
        #expect(module.snapshot == nil)
    }
}
