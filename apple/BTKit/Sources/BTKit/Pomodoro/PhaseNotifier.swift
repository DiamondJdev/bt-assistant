import Foundation
import os
import UserNotifications

public protocol PhaseNotifier: Sendable {
    func schedule(phase: PomodoroPhase, at date: Date) async
    func cancelAll() async
}

/// Schedules the phase-end notification when a phase starts, so it fires even
/// if the app is not running. One request id, so rescheduling replaces it.
public struct SystemPhaseNotifier: PhaseNotifier {
    static let requestID = "bt.pomodoro.phase-end"
    private static let logger = Logger(subsystem: "BTKit", category: "Pomodoro")

    public init() {}

    // UNUserNotificationCenter.current() is called lazily: it crashes in a
    // process without an app bundle, such as `swift test`.
    public func schedule(phase: PomodoroPhase, at date: Date) async {
        let center = UNUserNotificationCenter.current()
        do {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else { return }
            let content = UNMutableNotificationContent()
            content.title = "Pomodoro"
            content.body = phase == .work
                ? "Work block done. Time for a break."
                : "Break's over. Ready for the next block?"
            content.sound = .default
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: date
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try await center.add(UNNotificationRequest(identifier: Self.requestID, content: content, trigger: trigger))
        } catch {
            Self.logger.error("Could not schedule phase-end notification: \(error.localizedDescription)")
        }
    }

    public func cancelAll() async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.requestID])
    }
}
