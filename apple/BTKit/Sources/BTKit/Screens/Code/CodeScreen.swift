import SwiftUI

/// Code: the project index on the left drives a header, roadmap, heat grid, Inside Focus and BT suggestions.
/// Built to match design/screens/Code.dc.html.
public struct CodeScreen: View {
    @Bindable var store: AppStore
    @State private var sheet: CodeSheet?
    public init(store: AppStore) { self.store = store }

    public var body: some View {
        SandGrid(columns: 4, rows: [210, 319, 319], minRowHeights: [200, 220, 190]) {
            CodeProjectList(store: store, edit: { sheet = .details($0) })
                .gridCell(0, 0, rows: 3)
            if let project = store.project(store.selectedProjectID) ?? store.projects.first {
                let week = CodeWeek(activity: project.activity, now: store.now, calendar: store.calendar)
                CodeHeadCell(project: project, week: week, edit: { sheet = .details(project) })
                    .gridCell(1, 0, columns: 3)
                CodeRoadmapCell(project: project, now: store.now, calendar: store.calendar, askBT: {
                    if project.stages.isEmpty {
                        Task { await store.draftRoadmap(projectID: project.id) }
                    } else {
                        Task { await store.editRoadmap(projectID: project.id) }
                    }
                }, edit: { sheet = .roadmap(project) })
                .gridCell(1, 1, rows: 2)
                CodeHeatCell(project: project, week: week)
                    .gridCell(2, 1, columns: 2)
                CodeInsideFocusCell(week: week)
                    .gridCell(2, 2)
                CodeSuggestCell(store: store, project: project, week: week)
                    .gridCell(3, 2)
            }
        }
        .frame(minWidth: BTMetrics.minContentWidth)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .roadmap(let project): CodeRoadmapEditor(store: store, project: project)
            case .details(let project): CodeProjectEditor(store: store, project: project)
            }
        }
    }
}

/// The one sheet Code can show at a time.
enum CodeSheet: Identifiable {
    case roadmap(Project)
    case details(Project)

    var id: String {
        switch self {
        case .roadmap(let project): "roadmap-\(project.id)"
        case .details(let project): "details-\(project.id)"
        }
    }
}

/// Column 4 of the header while Code is open: "Week 9 · Oct 19 – 25".
public struct CodeHeaderContext: View {
    @Bindable var store: AppStore
    public init(store: AppStore) { self.store = store }

    public var body: some View {
        Text(CodeTermWeek.label(now: store.now, calendar: store.calendar))
    }
}

/// Term week numbering for the header and the "All projects" label.
enum CodeTermWeek {
    // ponytail: fixed fall-term start (the week of Aug 24); read it from a term setting once one exists.
    static let termStart = DateComponents(month: 8, day: 24)

    /// 1-based week of the term containing `now`.
    static func number(now: Date, calendar: Calendar) -> Int {
        let year = calendar.component(.year, from: now)
        func start(_ y: Int) -> Date {
            var c = termStart
            c.year = y
            let day = calendar.date(from: c) ?? now
            return calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? day
        }
        let begin = start(year) <= now ? start(year) : start(year - 1)
        return (calendar.dateComponents([.weekOfYear], from: begin, to: now).weekOfYear ?? 0) + 1
    }

    /// "Week 9 · Oct 19 – 25", or "Oct 26 – Nov 1" across months.
    static func label(now: Date, calendar: Calendar) -> String {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now),
              let last = calendar.date(byAdding: .day, value: 6, to: week.start) else { return "" }
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        let first = f.string(from: week.start)
        f.dateFormat = calendar.isDate(week.start, equalTo: last, toGranularity: .month) ? "d" : "MMM d"
        return "Week \(number(now: now, calendar: calendar)) · \(first) – \(f.string(from: last))"
    }
}

/// A mono cell label with an accent note number: "1 · When you work on it".
struct CodeNoteLabel: View {
    let number: String
    let text: String

    var body: some View {
        (Text(number).foregroundStyle(Color.btAccentText) + Text(" · \(text)").foregroundStyle(Color.btMuted))
            .font(.mono(11))
            .tracking(11 * 0.08)
            .textCase(.uppercase)
    }
}
