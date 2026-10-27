import SwiftUI

/// Focus session controls on the left, the compact LineRing on the right.
struct TodayFocusCell: View {
    let store: AppStore

    private var status: String {
        let f = store.focus
        if f.remainingSeconds == 0 { return "done" }
        if f.isPaused { return "paused" }
        return f.mode == .break ? "break" : "running"
    }

    var body: some View {
        let f = store.focus
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Button { store.open(.focus) } label: {
                    Text("Focus →\nSession \(f.number) of \(f.plannedCount) · \(status)")
                        .monoLabel()
                        .lineSpacing(3)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Focus. Session \(f.number) of \(f.plannedCount), \(status)")
                Spacer(minLength: 12)
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.taskTitle)
                        Text(store.project(f.projectID)?.name ?? "").foregroundStyle(Color.btMuted)
                    }
                    .interStyle(22, .medium, tracking: -0.01)
                    HStack(spacing: 8) {
                        Button(f.isPaused ? "Resume" : "Pause") { store.toggleFocusPause() }
                            .buttonStyle(.pill(.primary))
                        Button("+5 min") { store.addFiveMinutes() }
                            .buttonStyle(.pill(.secondary))
                    }
                    .frame(minHeight: 44)
                }
            }
            .padding(BTMetrics.cellPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .dashedEdges(bottom: false)

            ZStack {
                LineRing(progress: f.progress, tint: f.mode == .break ? .btBreakGreen : .btAccent, geometry: .compact)
                    .frame(width: 280, height: 280)
                Text(f.clock)
                    .font(.mono(26, .medium))
                    .tracking(26 * -0.02)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Focus ring: \(f.clock) remaining")
        }
        .dashedEdges()
    }
}

/// BT's suggestion to book the next session, then its confirmation.
struct TodayBTCell: View {
    let store: AppStore

    var body: some View {
        Group {
            if let booked = store.todayBookedEvent {
                BTStatement(label: "BT · read 3 modules", meta: TodayFormat.clock(store.now, store.calendar),
                            clauses: store.todayConfirmation(booked)) {
                    Button("Undo") { store.undoTodayBooking() }.buttonStyle(.pill(.secondary))
                    Button("See in Calendar") { store.open(.calendar(.week, eventID: booked.id)) }
                        .buttonStyle(.pill(.secondary))
                }
            } else {
                BTStatement(label: "BT · read 3 modules", meta: TodayFormat.clock(store.now, store.calendar),
                            clauses: store.todayProposal) {
                    if let slot = store.todayBookingSlot {
                        Button("Book \(TodayFormat.clock(slot.start, store.calendar))") {
                            store.bookTodaySession()
                        }
                        .buttonStyle(.pill(.cta))
                    }
                    Button("Reply") { store.open(.bt()) }.buttonStyle(.pill(.secondary))
                }
            }
        }
        .padding(BTMetrics.cellPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashedEdges(right: false)
    }
}
