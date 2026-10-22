import SwiftUI

/// The large ring, countdown, corner labels and session controls.
struct FocusRingStage: View {
    let store: AppStore
    let summary: FocusSummary

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                LineRing(
                    progress: store.focus.progress,
                    tint: summary.isBreak ? .btBreakGreen : .btAccent,
                    geometry: .focus
                )
                .frame(maxWidth: 500, maxHeight: 500)
                VStack(spacing: 4) {
                    Text(store.focus.clock)
                        .interStyle(92, .medium, tracking: -0.055)
                        .monospacedDigit()
                    Text(summary.ofLabel)
                        .monoLabel(color: summary.ofIsAlert ? .btAccentText : .btMuted)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(store.focus.clock) remaining, \(summary.ofLabel)")
            }
            controls
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            corner(summary.sessionLabel, summary.taskLabel, alignment: .leading)
        }
        .overlay(alignment: .topTrailing) {
            corner(summary.nextStepLabel, summary.nextEventLabel, alignment: .trailing)
        }
        .dashedEdges(right: true, bottom: false)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button(summary.pauseLabel) { store.toggleFocusPause() }
                .buttonStyle(.pill(.primary, size: .large))
            Button("+5 min") { store.addFiveMinutes() }
                .buttonStyle(.pill(.secondary, size: .large))
            Button(summary.endLabel) { store.endOrStartNext() }
                .buttonStyle(.pill(.secondary, size: .large))
        }
    }

    private func corner(_ top: String, _ bottom: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(top)
            Text(bottom)
        }
        .monoLabel()
        .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
        .padding(BTMetrics.cellPadding)
    }
}
