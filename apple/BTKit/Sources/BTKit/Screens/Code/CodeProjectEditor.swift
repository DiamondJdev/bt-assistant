import SwiftUI

/// Sheet for a project's name, repo path and weekly goal, and for removing the project.
struct CodeProjectEditor: View {
    let store: AppStore
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var path: String
    @State private var bookmark: Data?
    @State private var picking = false
    @State private var goal: String
    @State private var confirmingRemove = false
    @State private var errorMessage: String?

    init(store: AppStore, project: Project) {
        self.store = store
        self.project = project
        _name = State(initialValue: project.name)
        _path = State(initialValue: project.path)
        _goal = State(initialValue: project.weeklyGoalHours.map { $0 == $0.rounded() ? String(Int($0)) : String($0) } ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CodeSheetHeader(
                label: "Edit project · \(project.name)", title: "Project details",
                detail: "Coding time is matched to this project by its editor folder name, so renaming it here keeps its history."
            )
            .padding(BTMetrics.cellPadding)
            .dashedEdges(right: false, bottom: true)
            VStack(alignment: .leading, spacing: 18) {
                field("Name") {
                    TextField("Project name", text: $name)
                        .textFieldStyle(.plain)
                        .font(.inter(17, .semibold))
                        .frame(height: 32)
                        .overlay(alignment: .bottom) { Rectangle().fill(Color.btInk).frame(height: 1.5) }
                }
                field("Repo folder") {
                    HStack(spacing: 12) {
                        Text(path.isEmpty ? "None chosen" : path)
                            .font(.mono(12))
                            .foregroundStyle(path.isEmpty ? Color.btMuted : Color.btInk)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                            .overlay(alignment: .bottom) { Rectangle().fill(Color.btRule).frame(height: 1) }
                        Button("Choose…") { picking = true }.buttonStyle(.monoLink)
                    }
                    .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
                        guard case .success(let url) = result else { return }
                        path = url.path
                        bookmark = AppStore.repoBookmark(url)
                    }
                }
                field("Weekly goal") {
                    HStack(spacing: 8) {
                        TextField("None", text: $goal)
                            .textFieldStyle(.plain)
                            .font(.mono(12))
                            .frame(width: 80, height: 30)
                            .overlay(alignment: .bottom) { Rectangle().fill(Color.btRule).frame(height: 1) }
                            .accessibilityLabel("Weekly goal in hours")
                        Text("hours · leave blank for no goal").font(.inter(12)).foregroundStyle(Color.btMuted)
                    }
                }
            }
            .padding(BTMetrics.cellPadding)
            Spacer(minLength: 0)
            footer
                .padding(.horizontal, BTMetrics.cellPadding)
                .padding(.vertical, 16)
                .dashedEdges(right: false, bottom: false, top: true)
        }
        .frame(width: 520, height: 470)
        .codeSheetStyle()
    }

    @ViewBuilder private var footer: some View {
        if confirmingRemove {
            HStack(spacing: 12) {
                Text("Remove \(project.name)? Its roadmap and goal are deleted. Coding time stays on disk.")
                    .font(.inter(13))
                    .foregroundStyle(Color.btAccentDeep)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Keep") { confirmingRemove = false }
                    .buttonStyle(.pill(.secondary))
                    .keyboardShortcut(.cancelAction)
                Button("Remove") {
                    store.removeProject(project.id)
                    dismiss()
                }
                .buttonStyle(.pill(.cta))
            }
        } else {
            HStack(spacing: 12) {
                Button("Remove project") { confirmingRemove = true }
                    .buttonStyle(.plain)
                    .font(.inter(13))
                    .underline()
                    .foregroundStyle(Color.btAccentDeep)
                    .frame(minHeight: 36)
                if let errorMessage {
                    Text(errorMessage).font(.inter(12)).foregroundStyle(Color.btAccentText).lineLimit(2)
                }
                Spacer(minLength: 0)
                Button("Cancel") { dismiss() }
                    .buttonStyle(.pill(.secondary))
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .buttonStyle(.pill(.primary))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func field<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.inter(11)).foregroundStyle(Color.btMuted)
            content()
        }
    }

    private func save() {
        let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let hours = Double(trimmedGoal)
        guard trimmedGoal.isEmpty || hours != nil else {
            errorMessage = "Weekly goal must be a number of hours."
            return
        }
        do {
            try store.updateProject(project.id, name: name, path: path, weeklyGoalHours: hours, bookmark: bookmark)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Mono label, a 28pt title and a muted line: the top of every Code sheet.
struct CodeSheetHeader: View {
    let label: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).monoLabel()
            Text(title).interStyle(28, .medium, tracking: -0.035)
            Text(detail)
                .font(.inter(13))
                .foregroundStyle(Color.btMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// Sand ground and ink text for a sheet. The app is light-only, so system pieces
    /// (menus, focus rings) stay light even when macOS is dark.
    func codeSheetStyle() -> some View {
        background(Color.btGround)
            .foregroundStyle(Color.btInk)
            .tint(Color.btAccent)
            .environment(\.colorScheme, .light)
    }
}
