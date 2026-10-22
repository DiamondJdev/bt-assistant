import SwiftUI

/// "Afternoon,\nCameron" at 96pt with line-height 0.88.
struct TodayGreetingCell: View {
    let store: AppStore

    var body: some View {
        let size: CGFloat = 96
        // Negative spacing pulls the lines to ~0.88 line height.
        VStack(alignment: .leading, spacing: -size * 0.3) {
            Text("\(TodayFormat.greeting(store.now, store.calendar)),")
            Text(TodayFormat.ownerName)
        }
        .interStyle(size, .medium, tracking: -0.055)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .padding(BTMetrics.cellPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .dashedEdges(bottom: false)
    }
}

/// "Tell BT" composer. Enter or Send posts to BT and shows a confirmation.
struct TodayComposerCell: View {
    @Bindable var state: TodayState
    let store: AppStore

    init(store: AppStore) {
        self.store = store
        self.state = store.today
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer(minLength: 0)
            if let sent = state.sentText {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Sent to BT: “\(sent)”").font(.inter(15)).lineLimit(2)
                    Spacer(minLength: 0)
                    Button("Open thread →") { store.open(.bt(threadID: state.sentThreadID)) }
                        .buttonStyle(.monoLink)
                        .fixedSize()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.btAccent.opacity(0.06))
                .overlay(Rectangle().strokeBorder(Color.btAccent, style: StrokeStyle(lineWidth: 1, dash: BTMetrics.dash)))
            }
            Text("Tell BT").monoLabel()
            HStack(spacing: 10) {
                TextField("Move CHEM review to after work…", text: $state.draft)
                    .textFieldStyle(.plain)
                    .interStyle(24, tracking: -0.02)
                    .onSubmit { store.sendTodayDraft() }
                    .accessibilityLabel("Tell BT")
                Button { store.sendTodayDraft() } label: {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.btInkOnDark)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.btInk))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Send")
            }
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.btInk).frame(height: 1.5) }
        }
        .padding(BTMetrics.cellPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
}
