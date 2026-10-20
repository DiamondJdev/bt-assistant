/// Joins module snapshot fragments, in priority order, into one message context.
/// A fragment that would push the total past `budget` characters is skipped whole;
/// later, shorter fragments can still fit. Nil when nothing fits. Counts Unicode scalars,
/// as the server does.
func contextSnapshot(_ fragments: [String?], budget: Int = 2000) -> String? {
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
