import SwiftUI

/// Column 4, "Changes BT made": every BT write, newest first, each with Undo.
struct BTLedgerColumn: View {
    @Bindable var store: AppStore

    var body: some View {
        ScrollView { content }.scrollIndicators(.never)
    }

    var content: some View {
        let undone = store.ledger.filter(\.isUndone).count
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Changes BT made")
                Spacer()
                Text("Today · \(store.ledger.count - undone)")
            }
            .monoLabel()
            .padding(.bottom, 12)
            ForEach(store.ledger) { entry in
                BTLedgerRow(store: store, entry: entry)
            }
            if undone > 0 {
                Text("\(undone) change\(undone == 1 ? "" : "s") undone — reverted in Calendar, Code and memory.")
                    .font(.inter(13))
                    .foregroundStyle(Color.btMuted)
                    .padding(.vertical, 10)
            }
        }
        .padding(BTMetrics.cellPadding)
    }
}

private struct BTLedgerRow: View {
    let store: AppStore
    let entry: LedgerEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(BTFormat.clock(entry.time, store.calendar))
                .font(.mono(11)).foregroundStyle(Color.btMuted)
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(Self.kindLabel(entry.kind))
                    .monoLabel(10, color: entry.kind == .memory && !entry.isUndone ? .btAccentText : .btMuted)
                Text(entry.summary)
                    .font(.inter(14)).lineSpacing(3)
                    .strikethrough(entry.isUndone)
                    .foregroundStyle(entry.isUndone ? Color.btMuted : Color.btInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if entry.isUndone {
                Text("Undone").font(.inter(12)).foregroundStyle(Color.btMuted)
            } else {
                Button("Undo") { store.undo(entry.id) }
                    .buttonStyle(.plain)
                    .font(.inter(12))
                    .underline()
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .padding(.vertical, -14)
                    .accessibilityLabel("Undo \(entry.summary)")
            }
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.btRule).frame(height: 1) }
    }

    static func kindLabel(_ kind: ResultKind) -> String {
        kind == .todo ? "TO-DO" : kind.rawValue.uppercased()
    }
}
