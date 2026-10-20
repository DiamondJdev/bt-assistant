import Foundation
import SwiftData

/// One logged work phase. Attributes are optional or defaulted so the model
/// stays CloudKit-compatible.
@Model
final class FocusSession {
    var start: Date = Date.distantPast
    var end: Date = Date.distantPast
    var focusedSeconds: Double = 0
    var label: String?
    /// `EKEvent.calendarItemIdentifier` of the calendar event this session
    /// was planned under. Unused until focus sessions link to events.
    var eventIdentifier: String?

    init(start: Date, end: Date, focusedSeconds: Double, label: String? = nil, eventIdentifier: String? = nil) {
        self.start = start
        self.end = end
        self.focusedSeconds = focusedSeconds
        self.label = label
        self.eventIdentifier = eventIdentifier
    }
}

/// Every SwiftData model in BTKit, for building the app's one `ModelContainer`.
public enum BTModels {
    public static let all: [any PersistentModel.Type] = [FocusSession.self]
}

@MainActor
struct FocusLog {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func record(_ interval: FocusInterval, label: String?) throws {
        let seconds = interval.end.timeIntervalSince(interval.start)
        context.insert(FocusSession(start: interval.start, end: interval.end, focusedSeconds: seconds, label: label))
        try context.save()
    }

    /// Sessions count toward the day they ended on.
    func totalFocused(on day: Date, calendar: Calendar = .current) -> TimeInterval {
        totalFocused(lastDays: 1, endingOn: day, calendar: calendar)
    }

    func totalFocused(lastDays: Int, endingOn day: Date, calendar: Calendar = .current) -> TimeInterval {
        guard let lastDay = calendar.dateInterval(of: .day, for: day),
              let from = calendar.date(byAdding: .day, value: 1 - lastDays, to: lastDay.start)
        else { return 0 }
        let to = lastDay.end
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.end >= from && $0.end < to }
        )
        let sessions = (try? context.fetch(descriptor)) ?? []
        return sessions.reduce(0) { $0 + $1.focusedSeconds }
    }
}
