import SwiftUI

/// Column 1: the weekly total for all projects, then one row per project and "+ Track a repo".
struct CodeProjectList: View {
    @Bindable var store: AppStore
    let edit: (Project) -> Void

    var body: some View {
        let weeks = store.projects.map { CodeWeek(activity: $0.activity, now: store.now, calendar: store.calendar) }
        let total = weeks.reduce(0) { $0 + $1.weekMinutes }
        VStack(alignment: .leading, spacing: 0) {
            CodeAllProjects(
                total: total,
                lastWeek: weeks.reduce(0) { $0 + $1.lastWeekMinutes },
                goalHours: store.code.allProjectsGoalHours,
                week: CodeTermWeek.number(now: store.now, calendar: store.calendar)
            )
            .padding(.horizontal, BTMetrics.cellPadding)
            .padding(.bottom, 18)
            ForEach(Array(zip(store.projects, weeks)), id: \.0.id) { project, week in
                CodeProjectRow(
                    project: project, week: week, share: total > 0 ? week.weekMinutes / total : 0,
                    isSelected: project.id == (store.selectedProjectID ?? store.projects.first?.id)
                ) {
                    store.selectedProjectID = project.id
                }
                .contextMenu {
                    Button("Edit project…") { edit(project) }
                }
            }
            CodeTrackRepo(store: store)
                .padding(.horizontal, BTMetrics.cellPadding)
                .padding(.top, 14)
            Spacer(minLength: 0)
        }
        .padding(.vertical, BTMetrics.cellPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashedEdges(right: true, bottom: false)
    }
}

struct CodeAllProjects: View {
    static let segments = 24
    let total: Double
    let lastWeek: Double
    let goalHours: Double
    let week: Int

    var body: some View {
        let filled = goalHours > 0 ? min(Self.segments, Int((total / 60 / goalHours * Double(Self.segments)).rounded())) : 0
        VStack(alignment: .leading, spacing: 6) {
            Text("All projects · week \(week)").monoLabel()
            Text(CodeWeek.duration(minutes: total)).interStyle(44, .medium, tracking: -0.05)
            TickBar(count: Self.segments, filled: filled, height: 12)
                .accessibilityLabel(String(format: "%.1f of %@ weekly goal", total / 60, CodeSuggestions.hours(goalHours)))
            Text("Goal \(CodeSuggestions.hours(goalHours)) · \(CodeWeek.delta(minutes: total - lastWeek)) vs last week")
                .monoLabel(11, tracking: 0)
        }
    }
}

struct CodeProjectRow: View {
    let project: Project
    let week: CodeWeek
    let share: Double
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        let status = week.status
        Button(action: select) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(project.name).interStyle(20, .medium, tracking: -0.02).lineLimit(1)
                    Spacer()
                    Text(CodeWeek.duration(minutes: week.weekMinutes)).font(.mono(12))
                }
                CodeShareBar(share: share, fill: .btInk, track: .btFillClass, height: 4)
                HStack(alignment: .bottom, spacing: 10) {
                    Text(status.label).monoLabel(11, tracking: 0.06, color: status.isAccent ? .btAccentText : .btMuted)
                    Spacer()
                    CodeSpark(minutes: week.dailyMinutes, todayIndex: week.todayIndex, isSelected: isSelected)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, BTMetrics.cellPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.btPaper : .clear)
            .overlay(alignment: .leading) {
                if isSelected { Rectangle().fill(Color.btAccent).frame(width: 3) }
            }
            .overlay(alignment: .top) { Rectangle().fill(Color.btRule).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(project.name), \(CodeWeek.duration(minutes: week.weekMinutes)) this week, \(status.label)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A thin horizontal bar filled to `share` (0…1).
struct CodeShareBar: View {
    let share: Double
    let fill: Color
    let track: Color
    let height: CGFloat

    var body: some View {
        GeometryReader { g in
            track.overlay(alignment: .leading) {
                fill.frame(width: g.size.width * min(1, max(0, share)))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// 7 daily bars, 6pt wide; days after today are drawn in track color.
struct CodeSpark: View {
    static let pointsPerHour: CGFloat = 6
    static let maxHeight: CGFloat = 20
    let minutes: [Double]
    let todayIndex: Int
    let isSelected: Bool

    static func height(minutes: Double) -> CGFloat {
        min(maxHeight, max(2, (minutes / 60 * pointsPerHour).rounded()))
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(minutes.indices, id: \.self) { i in
                Rectangle()
                    .fill(i > todayIndex ? Color.btTrack : (isSelected ? Color.btInk : Color.btSubtle))
                    .frame(width: 6, height: Self.height(minutes: minutes[i]))
            }
        }
        .frame(height: Self.maxHeight, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

/// "+ Track a repo": a dashed button that opens a folder picker. Picking the folder is what grants
/// the sandboxed app read access to the repo.
struct CodeTrackRepo: View {
    @Bindable var store: AppStore
    @State private var picking = false

    var body: some View {
        Button { picking = true } label: {
            Text("+ Track a repo").font(.inter(13))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(Rectangle().strokeBorder(Color.btSubtle, style: StrokeStyle(lineWidth: 1, dash: BTMetrics.dash)))
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            store.trackRepo(path: url.path, bookmark: AppStore.repoBookmark(url))
        }
    }
}
