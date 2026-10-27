import SwiftUI

/// Where a cell sits in a `SandGrid`. Zero-based column and row.
public struct GridPlacement: Equatable, Sendable {
    public var column: Int
    public var row: Int
    public var columnSpan: Int
    public var rowSpan: Int

    public init(column: Int, row: Int, columnSpan: Int = 1, rowSpan: Int = 1) {
        self.column = column
        self.row = row
        self.columnSpan = columnSpan
        self.rowSpan = rowSpan
    }
}

private struct GridPlacementKey: LayoutValueKey {
    static let defaultValue = GridPlacement(column: 0, row: 0)
}

public extension View {
    /// Places this view in the enclosing `SandGrid`.
    func gridCell(_ column: Int, _ row: Int, columns: Int = 1, rows: Int = 1) -> some View {
        layoutValue(key: GridPlacementKey.self, value: GridPlacement(column: column, row: row, columnSpan: columns, rowSpan: rows))
    }
}

/// A grid of equal columns and fractional rows, like the CSS grids in the mockups.
/// Children place themselves with `.gridCell(column, row, columns:, rows:)`.
/// Row fractions come from `grid-template-rows` (e.g. `[1, 1.25, 0.95]`).
public struct SandGrid: Layout {
    public var columns: Int
    public var rows: [CGFloat]
    public var minRowHeights: [CGFloat]

    public init(columns: Int = 4, rows: [CGFloat], minRowHeights: [CGFloat] = []) {
        self.columns = columns
        self.rows = rows
        self.minRowHeights = minRowHeights
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let minHeight = rows.indices.reduce(0) { $0 + minRow($1) }
        return CGSize(
            width: proposal.width ?? BTMetrics.minContentWidth,
            height: max(proposal.height ?? minHeight, minHeight)
        )
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let colWidth = bounds.width / CGFloat(columns)
        let heights = rowHeights(total: bounds.height)
        var offsets: [CGFloat] = [0]
        for h in heights { offsets.append(offsets.last! + h) }

        for subview in subviews {
            let p = subview[GridPlacementKey.self]
            let lastRow = min(p.row + p.rowSpan, heights.count)
            let frame = CGRect(
                x: bounds.minX + CGFloat(p.column) * colWidth,
                y: bounds.minY + offsets[p.row],
                width: colWidth * CGFloat(p.columnSpan),
                height: offsets[lastRow] - offsets[p.row]
            )
            subview.place(at: frame.origin, proposal: ProposedViewSize(frame.size))
        }
    }

    private func minRow(_ index: Int) -> CGFloat {
        index < minRowHeights.count ? minRowHeights[index] : 0
    }

    /// Splits the height by fraction, then lifts rows to their minimums
    /// and takes the difference back from the rows that have room.
    func rowHeights(total: CGFloat) -> [CGFloat] {
        let sum = rows.reduce(0, +)
        var heights = rows.map { total * $0 / sum }
        var fixed = Set<Int>()
        while let short = heights.indices.first(where: { !fixed.contains($0) && heights[$0] < minRow($0) }) {
            fixed.insert(short)
            heights[short] = minRow(short)
            let free = heights.indices.filter { !fixed.contains($0) }
            let left = total - fixed.reduce(0) { $0 + heights[$1] }
            let freeSum = free.reduce(0) { $0 + rows[$1] }
            for i in free { heights[i] = freeSum > 0 ? max(0, left) * rows[i] / freeSum : 0 }
        }
        return heights
    }
}

/// Draws the dashed right and bottom borders every grid cell has.
public struct DashedEdges: Shape {
    public var right = true
    public var bottom = true
    public var left = false
    public var top = false

    public init(right: Bool = true, bottom: Bool = true, left: Bool = false, top: Bool = false) {
        self.right = right
        self.bottom = bottom
        self.left = left
        self.top = top
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = rect.insetBy(dx: 0.5, dy: 0.5)
        if right { path.move(to: CGPoint(x: r.maxX, y: r.minY)); path.addLine(to: CGPoint(x: r.maxX, y: r.maxY)) }
        if bottom { path.move(to: CGPoint(x: r.minX, y: r.maxY)); path.addLine(to: CGPoint(x: r.maxX, y: r.maxY)) }
        if left { path.move(to: CGPoint(x: r.minX, y: r.minY)); path.addLine(to: CGPoint(x: r.minX, y: r.maxY)) }
        if top { path.move(to: CGPoint(x: r.minX, y: r.minY)); path.addLine(to: CGPoint(x: r.maxX, y: r.minY)) }
        return path
    }
}

public extension View {
    /// 1px dashed `line` borders on the chosen edges.
    func dashedEdges(right: Bool = true, bottom: Bool = true, left: Bool = false, top: Bool = false) -> some View {
        overlay(
            DashedEdges(right: right, bottom: bottom, left: left, top: top)
                .stroke(Color.btLine, style: StrokeStyle(lineWidth: 1, dash: BTMetrics.dash))
                .allowsHitTesting(false)
        )
    }
}

/// A grid cell: 20pt padding, a mono label row on top, content pushed to the bottom.
public struct GridCell<Content: View, Meta: View>: View {
    let label: String
    let right: Bool
    let bottom: Bool
    let meta: Meta
    let content: Content

    public init(
        _ label: String,
        right: Bool = true,
        bottom: Bool = true,
        @ViewBuilder meta: () -> Meta = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.right = right
        self.bottom = bottom
        self.meta = meta()
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).monoLabel()
                Spacer(minLength: 8)
                meta.monoLabel()
            }
            Spacer(minLength: 12)
            content
        }
        .padding(BTMetrics.cellPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashedEdges(right: right, bottom: bottom)
    }
}

#Preview("SandGrid") {
    SandGrid(rows: [1, 1.25, 0.95]) {
        GridCell("Thu 22 Oct") { Text("12:46").interStyle(64, .medium, tracking: -0.045) }
            .gridCell(0, 0)
        GridCell("Calendar", meta: { Text("4 remaining →") }) { Text("Agenda") }
            .gridCell(1, 0, columns: 2)
        GridCell("Code time", right: false) { Text("3h 12m") }
            .gridCell(3, 0)
        GridCell("Focus") { Text("Ring") }
            .gridCell(0, 1, columns: 2)
        GridCell("BT", right: false) { Text("Statement") }
            .gridCell(2, 1, columns: 2)
        GridCell("Greeting", bottom: false) { Text("Afternoon") }
            .gridCell(0, 2, columns: 2)
        GridCell("Tell BT", right: false, bottom: false) { Text("Composer") }
            .gridCell(2, 2, columns: 2)
    }
    .frame(width: 1200, height: 760)
    .background(Color.btGround)
    .foregroundStyle(Color.btInk)
    .onAppear { BTFont.register() }
}
