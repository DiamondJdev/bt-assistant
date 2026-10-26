import Foundation

// Real sources replace `SampleData` through these. Each returns plain store values.

/// EventKit (Apple and Google through macOS Calendar). `AppStore` reads a window of events,
/// writes edits back and reloads when `changeToken` moves.
@MainActor
public protocol CalendarSource: AnyObject {
    var changeToken: Int { get }
    var hasAccess: Bool { get }
    func events(in interval: DateInterval) -> [CalendarEvent]
    /// Returns the event as stored; EventKit can give an edited occurrence a new id.
    func save(_ event: CalendarEvent) throws -> CalendarEvent
    func delete(_ event: CalendarEvent) throws
}

/// Editor coding sessions, one project per editor project name. Roadmaps and goals stay in `AppStore`.
@MainActor
public protocol CodeActivitySource: AnyObject {
    var changeToken: Int { get }
    /// Projects with the activity that started at or after `start`, busiest first.
    func projects(since start: Date) -> [Project]
}
