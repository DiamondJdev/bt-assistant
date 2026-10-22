import SwiftUI

/// Date, term week and the live 64pt time.
struct TodayClockCell: View {
    let store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(TodayFormat.dayLabel(store.now, store.calendar))\n\(TodayFormat.termLabel(store.now, store.calendar))")
                .monoLabel()
                .lineSpacing(3)
            Spacer(minLength: 12)
            Text(TodayFormat.clock(store.now, store.calendar))
                .interStyle(64, .medium, tracking: -0.045)
                .monospacedDigit()
                .accessibilityLabel("Time \(TodayFormat.clock(store.now, store.calendar))")
        }
        .padding(BTMetrics.cellPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashedEdges()
    }
}

/// Rows still to come today. "N remaining →" opens Calendar Day.
struct TodayAgendaCell: View {
    let store: AppStore

    var body: some View {
        let rows = store.todayAgenda
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Calendar").monoLabel()
                Spacer()
                Button("\(rows.count) remaining →") { store.open(.calendar(.day, date: store.now)) }
                    .buttonStyle(.monoLink)
                    .accessibilityLabel("\(rows.count) remaining, open Calendar day")
            }
            .padding(.bottom, 10)
            // Rows that don't fit are clipped; the cell keeps the grid's height.
            Color.clear
                .overlay(alignment: .topLeading) {
                    VStack(spacing: 4) { ForEach(rows) { AgendaRowView(row: $0) } }
                }
                .clipped()
        }
        .padding(BTMetrics.cellPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashedEdges()
    }
}

private struct AgendaRowView: View {
    let row: AgendaRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(row.time)
                .font(.mono(12))
                .foregroundStyle(row.isHot ? Color.btAccentText : .btMuted)
                .frame(width: 64, alignment: .leading)
            Text(row.title)
                .font(.inter(17, .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.meta)
                .font(.mono(12))
                .foregroundStyle(row.isBooked ? Color.btAccentText : .btMuted)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.btRule).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }
}

/// Today's coding total against a 4h goal. The whole cell opens Code.
struct TodayCodeTimeCell: View {
    let store: AppStore

    var body: some View {
        let summary = store.todayCodeTime
        Button { store.open(.code(projectID: nil)) } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Code time").monoLabel()
                    Spacer()
                    Text("Goal 4h").monoLabel()
                }
                Spacer(minLength: 12)
                VStack(alignment: .leading, spacing: 14) {
                    Text(summary.totalText).interStyle(52, .medium, tracking: -0.04)
                    TickBar(count: CodeTimeSummary.segments, filled: summary.filledSegments)
                        .accessibilityLabel("\(summary.percentOfGoal) percent of daily coding goal")
                    Text(summary.perProject.isEmpty ? "No code yet today →" : "\(summary.breakdown) →")
                        .monoLabel(tracking: 0.06)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .padding(BTMetrics.cellPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Code time \(summary.totalText), open Code")
        .dashedEdges(right: false)
    }
}
