import Charts
import SwiftUI

struct CodingView: View {
    let module: CodingModule
    @State private var range: Range = .today

    enum Range: String, CaseIterable, Identifiable {
        case today = "Today"
        case week = "7 Days"
        var id: Self { self }
        var days: Int { self == .today ? 1 : 7 }
    }

    var body: some View {
        // Reading `changeToken` refreshes the pane after each ingest; the timeline
        // refreshes it as the open session ages out.
        let _ = module.changeToken
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    chart
                    totals
                }
                .padding(32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Today: \(PomodoroModule.format(module.stats(days: 1).total))")
                .font(.largeTitle)
            if let open = module.openSession {
                Text("Now in \(open.project) (\(open.language)) since \(open.start.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(.secondary)
            } else {
                Text("No open session")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var chart: some View {
        let calendar = Calendar.current
        let now = module.now()
        let days = codingDays(7, endingOn: now, calendar: calendar)
        let end = calendar.dateInterval(of: .day, for: now)?.end ?? now
        let sessions = module.sessions(from: days[0], to: end)
        return Chart(sessions.indices, id: \.self) { index in
            let session = sessions[index]
            BarMark(
                x: .value("Day", calendar.startOfDay(for: session.start), unit: .day),
                y: .value("Minutes", session.duration / 60)
            )
            .foregroundStyle(by: .value("Project", session.project))
        }
        .chartXScale(domain: days[0]...(days.last ?? now) + 24 * 60 * 60)
        .chartYAxisLabel("Minutes")
        .frame(height: 200)
    }

    private var totals: some View {
        let stats = module.stats(days: range.days)
        return VStack(alignment: .leading, spacing: 12) {
            Picker("Range", selection: $range) {
                ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 240)
            HStack(alignment: .top, spacing: 32) {
                list("Projects", stats.byProject)
                list("Languages", stats.byLanguage)
            }
        }
    }

    private func list(_ title: String, _ totals: [CodingTotal]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            if totals.isEmpty {
                Text("Nothing yet").foregroundStyle(.secondary)
            }
            ForEach(totals, id: \.name) { total in
                HStack {
                    Text(total.name)
                    Spacer()
                    Text(PomodoroModule.format(total.seconds)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
        .frame(minWidth: 200, alignment: .leading)
    }
}
