/// Joins module snapshot fragments, in priority order, into one message context.
/// A fragment that would push the total past `budget` characters is skipped whole;
/// later, shorter fragments can still fit. Nil when nothing fits. Counts Unicode scalars,
/// as the server does.
/// Characters of module context sent with each message.
let contextSnapshotBudget = 2000

func contextSnapshot(_ fragments: [String?], budget: Int = contextSnapshotBudget) -> String? {
    var kept: [String] = []
    var length = 0
    for case let fragment? in fragments where !fragment.isEmpty {
        let added = fragment.unicodeScalars.count + (kept.isEmpty ? 0 : 1)
        guard length + added <= budget else { continue }
        kept.append(fragment)
        length += added
    }
    return kept.isEmpty ? nil : kept.joined(separator: "\n")
}

/// How many non-empty fragments `contextSnapshot` leaves out for lack of room.
func omittedSnapshotCount(_ fragments: [String?], budget: Int = contextSnapshotBudget) -> Int {
    var length = 0
    var kept = 0
    var omitted = 0
    for case let fragment? in fragments where !fragment.isEmpty {
        let added = fragment.unicodeScalars.count + (kept == 0 ? 0 : 1)
        if length + added <= budget { length += added; kept += 1 } else { omitted += 1 }
    }
    return omitted
}
