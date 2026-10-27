import SwiftUI

/// Sheet for editing a project's roadmap by hand: stage names and order, task titles, statuses and order.
struct CodeRoadmapEditor: View {
    static let maxStages = 12
    static let maxTasks = 12

    let store: AppStore
    let project: Project
    private let expectedRevision: String
    @Environment(\.dismiss) private var dismiss
    @State private var stages: [RoadmapStage]
    @State private var errorMessage: String?

    init(store: AppStore, project: Project) {
        self.store = store
        self.project = project
        expectedRevision = (try? RoadmapEditing.revision(project.stages)) ?? ""
        _stages = State(initialValue: project.stages)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(BTMetrics.cellPadding)
                .dashedEdges(right: false, bottom: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach($stages) { $stage in
                        CodeStageEditor(
                            stage: $stage,
                            index: stages.firstIndex { $0.id == stage.id } ?? 0,
                            count: stages.count,
                            move: { from, to in stages.swapAt(from, to) },
                            remove: { id in stages.removeAll { $0.id == id } }
                        )
                    }
                    addStage
                }
                .padding(BTMetrics.cellPadding)
            }
            footer
                .padding(.horizontal, BTMetrics.cellPadding)
                .padding(.vertical, 16)
                .dashedEdges(right: false, bottom: false, top: true)
        }
        .frame(width: 680, height: 640)
        .codeSheetStyle()
    }

    private var header: some View {
        CodeSheetHeader(
            label: "Edit roadmap · \(project.name)", title: "Stages and tasks",
            detail: "Task statuses set progress. Finishing every task completes its stage; reopening a task reopens it."
        )
    }

    private var addStage: some View {
        Button {
            stages.append(RoadmapStage(index: stages.count + 1, name: "New stage", status: .next,
                                       tasks: [RoadmapTask(title: "New task", status: .todo)]))
        } label: {
            Text("+ Add stage").font(.inter(13))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(Rectangle().strokeBorder(Color.btSubtle, style: StrokeStyle(lineWidth: 1, dash: BTMetrics.dash)))
        .disabled(stages.count >= Self.maxStages)
        .opacity(stages.count >= Self.maxStages ? 0.4 : 1)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.inter(12))
                    .foregroundStyle(Color.btAccentText)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button("Cancel") { dismiss() }
                .buttonStyle(.pill(.secondary))
                .keyboardShortcut(.cancelAction)
            Button("Save roadmap", action: save)
                .buttonStyle(.pill(.primary))
                .keyboardShortcut(.defaultAction)
        }
    }

    private func save() {
        do {
            try store.saveRoadmap(projectID: project.id, stages: stages, expectedRevision: expectedRevision)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
