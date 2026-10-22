import SwiftUI

/// Columns 3–4, row 2 (note 1): 7 days × 16 hours of activity, with the best window.
struct CodeHeatCell: View {
    static let shades: [Color] = [0xE2D7CA, 0xCDBFAE, 0xA89888, 0x6B5C4C, 0x2E2218].map { Color(hex: $0) }
    static let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    static let hourLabels = ["8a", "12p", "4p", "8p"]
    static let labelWidth: CGFloat = 36

    let project: Project
    let week: CodeWeek

    var body: some View {
        let heat = week.heat
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                CodeNoteLabel(number: "1", text: "When you work on it")
                Spacer()
                Text(week.bestWindow).monoLabel()
            }
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Self.days, id: \.self) { day in
                        Text(day).monoLabel(10, tracking: 0).frame(maxHeight: .infinity)
                    }
                }
                .frame(width: Self.labelWidth, alignment: .leading)
                VStack(spacing: 3) {
                    ForEach(heat.indices, id: \.self) { d in
                        HStack(spacing: 3) {
                            ForEach(heat[d].indices, id: \.self) { h in cell(heat[d][h]) }
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Heat grid of \(project.name) activity by hour. \(week.bestWindow)")
            }
            HStack(spacing: 8) {
                Color.clear.frame(width: Self.labelWidth, height: 1)
                HStack(spacing: 0) {
                    ForEach(Self.hourLabels, id: \.self) { label in
                        Text(label).font(.mono(10)).foregroundStyle(Color.btMuted).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(BTMetrics.cellPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashedEdges(right: false, bottom: true)
    }

    @ViewBuilder private func cell(_ cell: HeatCell) -> some View {
        switch cell {
        case .future:
            Rectangle().strokeBorder(Color.btTrack, style: StrokeStyle(lineWidth: 1, dash: BTMetrics.dash))
        case .level(let level):
            Rectangle().fill(Self.shades[min(max(level, 0), Self.shades.count - 1)])
        }
    }
}

/// Column 3, row 3 (note 3): share of the week's work inside Focus sessions.
struct CodeInsideFocusCell: View {
    let week: CodeWeek

    var body: some View {
        let share = week.insideShare
        VStack(alignment: .leading, spacing: 0) {
            CodeNoteLabel(number: "3", text: "Inside Focus")
            Spacer(minLength: 12)
            VStack(alignment: .leading, spacing: 12) {
                Text(share.map { "\(Int(($0 * 100).rounded()))%" } ?? "—").interStyle(60, .medium, tracking: -0.05)
                GeometryReader { g in
                    let inside = share.map { (g.size.width - 3) * $0 } ?? 0
                    HStack(spacing: share.map { $0 > 0 && $0 < 1 ? 3 : 0 } ?? 0) {
                        Color.btInk.frame(width: inside)
                        CodeHatch()
                    }
                }
                .frame(height: 16)
                .accessibilityElement()
                .accessibilityLabel(share.map { "\(Int(($0 * 100).rounded()))% of work inside Focus" } ?? "No work this week")
                Text(week.insideNote).foregroundStyle(Color.btMuted).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(BTMetrics.cellPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashedEdges(right: true, bottom: false)
    }
}

/// 1pt vertical `line` strokes every 5pt: the "outside Focus" part of the bar.
struct CodeHatch: View {
    var body: some View {
        Canvas { context, size in
            var x: CGFloat = 0
            while x < size.width {
                context.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(.btLine))
                x += 5
            }
        }
    }
}
