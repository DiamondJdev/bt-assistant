/// BT's weekly summary per project, from Code.dc.html. The cells' numbers are derived;
/// this copy and the commit counts stay sample text until BT writes them and git feeds commits.
struct CodeSampleCopy {
    /// Three clauses (ink, muted, muted); notes 1, 2 and 3 follow each.
    var clauses: [String]
    var commits: String

    static func copy(for projectID: String) -> CodeSampleCopy {
        table[projectID] ?? CodeSampleCopy(
            clauses: ["Nothing tracked yet.", " There’s no roadmap yet", " — want me to draft one from the repo?"], commits: "0"
        )
    }

    private static let table: [String: CodeSampleCopy] = [
        "bt-client": CodeSampleCopy(clauses: [
            "Calendar sync is nearly done, and most of it happened in the evening.",
            " Stage 3 is 70% done with one task waiting on you",
            ", and you go twice as long without breaking when you’re in Focus.",
        ], commits: "14"),
        "tariffninja": CodeSampleCopy(clauses: [
            "Under 2 hours this week, down 40% from your average.",
            " PSC batch export is about halfway",
            ", and most of the work happened outside Focus.",
        ], commits: "5"),
        "mirai": CodeSampleCopy(clauses: [
            "A quiet week, about an hour so far.",
            " Essay feedback is 30% done",
            ", with nothing booked for the rest of the week.",
        ], commits: "3"),
        "waypave": CodeSampleCopy(clauses: [
            "No activity in 9 days.",
            " There’s no roadmap yet",
            " — want me to draft one from the repo?",
        ], commits: "0"),
    ]
}
