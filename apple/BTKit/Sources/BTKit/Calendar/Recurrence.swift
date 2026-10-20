import EventKit

public enum EditSpan: String, Sendable {
    case thisEvent = "this_event"
    case futureEvents = "future_events"

    var ekSpan: EKSpan {
        switch self {
        case .thisEvent: .thisEvent
        case .futureEvents: .futureEvents
        }
    }
}

public enum RecurrenceOption: Hashable, Sendable {
    case none, daily, weekly, biweekly, monthly, yearly
    /// A rule this app can't edit, such as "weekly on Mon and Wed". Holds a short description.
    case custom(String)

    static let editable: [RecurrenceOption] = [.none, .daily, .weekly, .biweekly, .monthly, .yearly]

    var label: String {
        switch self {
        case .none: "Never"
        case .daily: "Every day"
        case .weekly: "Every week"
        case .biweekly: "Every 2 weeks"
        case .monthly: "Every month"
        case .yearly: "Every year"
        case .custom(let text): "Custom repeat: \(text)"
        }
    }

    fileprivate var frequencyAndInterval: (EKRecurrenceFrequency, Int)? {
        switch self {
        case .daily: (.daily, 1)
        case .weekly: (.weekly, 1)
        case .biweekly: (.weekly, 2)
        case .monthly: (.monthly, 1)
        case .yearly: (.yearly, 1)
        case .none, .custom: nil
        }
    }

    fileprivate static func matching(_ rule: EKRecurrenceRule) -> RecurrenceOption? {
        let isPlain = rule.daysOfTheWeek == nil && rule.daysOfTheMonth == nil
            && rule.monthsOfTheYear == nil && rule.weeksOfTheYear == nil
            && rule.daysOfTheYear == nil && rule.setPositions == nil
        guard isPlain else { return nil }
        return editable.first { $0.frequencyAndInterval.map { $0 == (rule.frequency, rule.interval) } ?? false }
    }
}

func recurrenceOption(from rules: [EKRecurrenceRule]?) -> RecurrenceOption {
    guard let rules, !rules.isEmpty else { return .none }
    if rules.count == 1, let option = RecurrenceOption.matching(rules[0]) {
        return option
    }
    return .custom(rules.map(ruleText).joined(separator: "; "))
}

/// Rules to set on the event. `nil` means leave the event's rules unchanged (custom rules from other apps).
func recurrenceRules(for option: RecurrenceOption, end: Date?) -> [EKRecurrenceRule]? {
    if case .custom = option { return nil }
    guard let (frequency, interval) = option.frequencyAndInterval else { return [] }
    return [EKRecurrenceRule(
        recurrenceWith: frequency,
        interval: interval,
        end: end.map { EKRecurrenceEnd(end: $0) }
    )]
}

/// The RRULE part of the rule's description, e.g. `FREQ=WEEKLY;INTERVAL=1;BYDAY=MO,WE`.
private func ruleText(_ rule: EKRecurrenceRule) -> String {
    let description = rule.description
    guard let range = description.range(of: "RRULE ") else { return description }
    return String(description[range.upperBound...])
}
