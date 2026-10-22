import SwiftUI

/// Column 2, rows 2–3 (note 2): "Stage N of M" over a dashed timeline, or the empty state.
struct CodeRoadmapCell: View {
    let project: Project
    let now: Date
    let calendar: Calendar
    let askBT: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                CodeNoteLabel(number: "2", text: "Roadmap")
                Spacer()
                Button("Edit with BT", action: askBT).buttonStyle(.monoLink)
            }
            if let current = CodeRoadmapLabels.current(in: project) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Stage \(current.index)").interStyle(40, .medium, tracking: -0.045)
                    Text("of \(project.stages.count)").foregroundStyle(Color.btMuted)
                }
                timeline
                Spacer(minLength: 0)
                Button("Plan stage \(current.index + 1) with BT", action: askBT)
                    .buttonStyle(.pill(.secondary, size: .small))
            } else if !project.stages.isEmpty {
                timeline
                Spacer(minLength: 0)
            } else {
                empty
            }
        }
        .padding(BTMetrics.cellPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashedEdges(right: true, bottom: false)
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(project.stages) { stage in
                if stage.status == .current {
                    CodeCurrentStage(stage: stage, target: CodeRoadmapLabels.target(for: stage, in: project, now: now, calendar: calendar))
                } else {
                    CodeStageRow(stage: stage, when: CodeRoadmapLabels.when(stage, calendar: calendar))
                }
            }
        }
        .background(alignment: .leading) {
            DashedEdges(right: false, bottom: false, left: true)
                .stroke(Color.btLine, style: StrokeStyle(lineWidth: 1, dash: BTMetrics.dash))
                .frame(width: 1)
                .padding(.vertical, 8)
                .padding(.leading, 6)
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("No roadmap yet").interStyle(26, .medium, tracking: -0.03)
            Text("BT can draft stages from the repo’s README and open issues.")
                .foregroundStyle(Color.btMuted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Button("Draft a roadmap", action: askBT).buttonStyle(.pill(.cta, size: .large))
        }
        .padding(BTMetrics.cellPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .overlay(Rectangle().strokeBorder(Color.btLine, style: StrokeStyle(lineWidth: 1, dash: BTMetrics.dash)))
    }
}

/// A done, next or final stage: dot, number and name, and a date.
struct CodeStageRow: View {
    let stage: RoadmapStage
    let when: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            dot.frame(width: 14).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            Text(String(format: "%02d", stage.index)).font(.mono(11)) + Text("\u{00A0} \(stage.name)")
            Spacer(minLength: 8)
            Text(when).font(.mono(11))
        }
        .padding(.vertical, 8)
        .foregroundStyle(stage.status == .done ? Color.btMuted : Color.btInk)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var dot: some View {
        let dashed = StrokeStyle(lineWidth: 1.5, dash: [2, 2])
        switch stage.status {
        case .done:
            Circle().fill(Color.btInk).frame(width: 13, height: 13)
        case .final:
            Rectangle().fill(Color.btGround).overlay(Rectangle().strokeBorder(Color.btInk, style: dashed))
                .frame(width: 11, height: 11).rotationEffect(.degrees(45))
        case .next, .current:
            Circle().fill(Color.btGround).overlay(Circle().strokeBorder(Color.btInk, style: dashed))
                .frame(width: 13, height: 13)
        }
    }
}

/// The current stage: paper card with an accent border, progress, tasks and the target line.
struct CodeCurrentStage: View {
    let stage: RoadmapStage
    let target: String

    var body: some View {
        let pct = Int((stage.progress * 100).rounded())
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Circle().fill(Color.btAccent).frame(width: 13, height: 13)
                    .background(Circle().fill(Color.btAccent.opacity(0.25)).padding(-3))
                    .frame(width: 14)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                (Text(String(format: "%02d", stage.index)).font(.mono(11)).foregroundStyle(Color.btAccentText)
                    + Text("\u{00A0} \(stage.name)").font(.inter(17, .semibold)))
                Spacer(minLength: 8)
                Text("Now · \(pct)%").monoLabel(11, tracking: 0, color: .btAccentText)
            }
            VStack(alignment: .leading, spacing: 10) {
                CodeShareBar(share: stage.progress, fill: .btAccent, track: .btFillClass, height: 4)
                    .accessibilityLabel("\(pct)% done")
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(stage.tasks) { task in taskRow(task) }
                }
                Text(target).font(.inter(12)).foregroundStyle(Color.btMuted)
            }
            .padding(.leading, 26)
        }
        .padding(12)
        .background(Color.btPaper)
        .overlay(Rectangle().strokeBorder(Color.btAccent, lineWidth: 1.5))
        .padding(.vertical, 6)
        .padding(.leading, -6)
    }

    private func taskRow(_ task: RoadmapTask) -> some View {
        let done = task.status == .done
        return HStack(alignment: .firstTextBaseline) {
            Text(task.title).font(.inter(13)).strikethrough(done)
                .foregroundStyle(done ? Color.btMuted : Color.btInk)
            Spacer(minLength: 8)
            Text(CodeRoadmapLabels.label(task.status)).font(.mono(11))
                .foregroundStyle(task.status == .needsYou ? Color.btAccentText : Color.btMuted)
        }
        .accessibilityElement(children: .combine)
    }
}
