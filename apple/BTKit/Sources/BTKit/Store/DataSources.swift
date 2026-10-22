import Foundation

// Real sources replace `SampleData` through these. Each returns plain store values.

/// EventKit (Apple and Google through macOS Calendar) plus the Blackboard feed.
@MainActor
public protocol CalendarSource {
    func events(in interval: DateInterval) async throws -> [CalendarEvent]
    func save(_ event: CalendarEvent) async throws
    func delete(_ eventID: String) async throws
}

/// Editor and agent-session plugins plus git.
@MainActor
public protocol CodeActivitySource {
    func projects() async throws -> [Project]
}
