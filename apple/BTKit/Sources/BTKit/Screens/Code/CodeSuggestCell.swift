import SwiftUI

/// Column 4, row 3: booked vs goal, two suggestions that write to Calendar, Focus or BT, and "Ask about…".
struct CodeSuggestCell: View {
    @Bindable var store: AppStore
    let project: Project
    let week: CodeWeek

    var body: some View {
        let booked = CodeSuggestions.bookedMinutes(project, week: week, events: store.events)
        let fresh = CodeSuggestions.make(for: project, week: week, events: store.events)
        let accepted = store.code.accepted[project.id] ?? [:]
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("BT suggests").monoLabel()
                Spacer()
                Text(CodeSuggestions.bookedLabel(project, booked: booked)).monoLabel()
            }
            .padding(.bottom, 4)
            ForEach(fresh.indices, id: \.self) { slot in
                row(accepted[slot] ?? fresh[slot], slot: slot, isDone: accepted[slot] != nil)
            }
            Spacer(minLength: 12)
            ask
        }
        .padding(BTMetrics.cellPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ s: CodeSuggestion, slot: Int, isDone: Bool) -> some View {
        HStack(spacing: 10) {
            Text(s.title)
                .font(.inter(14, .medium))
                .lineSpacing(2)
                .strikethrough(isDone)
                .foregroundStyle(isDone ? Color.btMuted : Color.btInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button(isDone ? s.doneLabel : s.label) {
                store.acceptCodeSuggestion(s, slot: slot, projectID: project.id)
            }
            .buttonStyle(.pill(slot == 0 && !isDone ? .primary : .secondary, size: .small))
            .disabled(isDone)
            .fixedSize()
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.btRule).frame(height: 1) }
    }

    private var ask: some View {
        Button { store.open(.bt(projectID: project.id)) } label: {
            HStack(spacing: 8) {
                Text("Ask about \(project.name)…").font(.inter(16)).foregroundStyle(Color.btMuted)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.btInkOnDark)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.btInk))
            }
            .padding(.bottom, 6)
            .frame(minHeight: 44, alignment: .bottom)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.btInk).frame(height: 1.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ask BT about \(project.name)")
    }
}
