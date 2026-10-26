import SwiftUI

/// One stage in the roadmap editor: a paper card with the stage name, its tasks and "+ Add task".
struct CodeStageEditor: View {
    @Binding var stage: RoadmapStage
    let index: Int
    let count: Int
    let move: (Int, Int) -> Void
    let remove: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Text(String(format: "%02d", index + 1)).font(.mono(11)).foregroundStyle(Color.btAccentText)
                TextField("Stage name", text: $stage.name)
                    .textFieldStyle(.plain)
                    .font(.inter(17, .semibold))
                    .frame(height: 32)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.btInk).frame(height: 1.5) }
                    .accessibilityLabel("Stage \(index + 1) name")
                CodeEditorMoveButtons(index: index, count: count, label: "stage") { move(index, $0) }
                CodeEditorIconButton(symbol: "trash", label: "Remove stage \(index + 1)", isEnabled: count > 1) {
                    remove(stage.id)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach($stage.tasks) { $task in
                    let taskIndex = stage.tasks.firstIndex { $0.id == task.id } ?? 0
                    CodeTaskEditor(
                        task: $task, index: taskIndex, count: stage.tasks.count,
                        move: { stage.tasks.swapAt(taskIndex, $0) },
                        remove: { stage.tasks.removeAll { $0.id == task.id } }
                    )
                }
            }
            .padding(.leading, 30)
            Button("+ Add task") { stage.tasks.append(RoadmapTask(title: "New task", status: .todo)) }
                .buttonStyle(.monoLink)
                .padding(.leading, 30)
                .disabled(stage.tasks.count >= CodeRoadmapEditor.maxTasks)
                .opacity(stage.tasks.count >= CodeRoadmapEditor.maxTasks ? 0.4 : 1)
        }
        .padding(14)
        .background(Color.btPaper)
        .overlay(Rectangle().strokeBorder(Color.btLine, lineWidth: 1))
    }
}

/// One task row: title on a ruled line, a status menu, move and remove.
struct CodeTaskEditor: View {
    @Binding var task: RoadmapTask
    let index: Int
    let count: Int
    let move: (Int) -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField("Task title", text: $task.title)
                .textFieldStyle(.plain)
                .font(.inter(13))
                .strikethrough(task.status == .done)
                .foregroundStyle(task.status == .done ? Color.btMuted : Color.btInk)
                .frame(height: 30)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.btRule).frame(height: 1) }
                .accessibilityLabel("Task \(index + 1) title")
            CodeTaskStatusMenu(status: $task.status)
                .accessibilityLabel("Status for \(task.title)")
            CodeEditorMoveButtons(index: index, count: count, label: "task", move: move)
            CodeEditorIconButton(symbol: "minus", label: "Remove task \(index + 1)", isEnabled: count > 1, action: remove)
        }
    }
}

/// Mono status label in a ruled box that opens a menu of statuses.
struct CodeTaskStatusMenu: View {
    static let order: [RoadmapTaskStatus] = [.todo, .inProgress, .inReview, .needsYou, .done]
    @Binding var status: RoadmapTaskStatus

    /// "In review" from "IN REVIEW".
    static func title(_ status: RoadmapTaskStatus) -> String {
        let label = CodeRoadmapLabels.label(status).lowercased()
        return label.prefix(1).uppercased() + label.dropFirst()
    }

    var body: some View {
        Menu {
            Picker("Status", selection: $status) {
                ForEach(Self.order, id: \.self) { option in
                    Text(Self.title(option)).tag(option)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 6) {
                Text(CodeRoadmapLabels.label(status)).font(.mono(11)).tracking(11 * 0.06)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(status == .needsYou ? Color.btAccentText : Color.btInk)
            .padding(.horizontal, 10)
            .frame(width: 128, height: 30)
            .background(status == .needsYou ? Color.btAccentTint : Color.clear)
            .overlay(Rectangle().strokeBorder(status == .needsYou ? Color.btAccent : Color.btLine, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// Up and down chevrons for reordering.
struct CodeEditorMoveButtons: View {
    let index: Int
    let count: Int
    let label: String
    let move: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            CodeEditorIconButton(symbol: "chevron.up", label: "Move \(label) \(index + 1) up", isEnabled: index > 0) {
                move(index - 1)
            }
            CodeEditorIconButton(symbol: "chevron.down", label: "Move \(label) \(index + 1) down", isEnabled: index < count - 1) {
                move(index + 1)
            }
        }
    }
}

/// A bare 28pt glyph button in ink that fades out when disabled.
struct CodeEditorIconButton: View {
    let symbol: String
    let label: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.btInk)
        .opacity(isEnabled ? 1 : 0.25)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }
}
