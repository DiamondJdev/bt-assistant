import SwiftUI

/// N thin segments with 3pt gaps: `ink` up to `filled`, `track` after.
/// Segments in `dashedRange` draw as a dashed outline ("booked but not done").
public struct TickBar: View {
    let count: Int
    let filled: Int
    let dashed: Int
    let height: CGFloat
    let color: Color

    public init(count: Int = 24, filled: Int, dashed: Int = 0, height: CGFloat = 18, color: Color = .btInk) {
        self.count = count
        self.filled = filled
        self.dashed = dashed
        self.height = height
        self.color = color
    }

    public var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<count, id: \.self) { i in
                if i < filled {
                    RoundedRectangle(cornerRadius: 1).fill(color)
                } else if i < filled + dashed {
                    RoundedRectangle(cornerRadius: 1)
                        .strokeBorder(Color.btInk, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                } else {
                    RoundedRectangle(cornerRadius: 1).fill(Color.btTrack)
                }
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("\(filled) of \(count)")
    }
}

/// The signature ring: short twisted line segments around a wobbling circle.
/// Geometry is in a 300×300 box and scales to the frame.
/// Defaults are the Focus ring; Today uses `.compact`.
public struct LineRing: View {
    public struct Geometry: Sendable {
        public var count: Int
        public var inner: CGFloat
        public var innerWobble: CGFloat
        public var outer: CGFloat
        public var outerWobble: CGFloat
        public var twist: CGFloat
        public var lineWidth: CGFloat

        /// Focus: r1 = 92 + 9·sin(3a + 0.6), r2 = 132 + 4.5·sin(3a + 0.6), twist 0.36.
        public static let focus = Geometry(count: 220, inner: 92, innerWobble: 9, outer: 132, outerWobble: 4.5, twist: 0.36, lineWidth: 1.1)
        /// Today: r1 = 62 + 10·sin(3a + 0.6), r2 = 104 + 6·sin(3a + 0.6), twist 0.42.
        public static let compact = Geometry(count: 160, inner: 62, innerWobble: 10, outer: 104, outerWobble: 6, twist: 0.42, lineWidth: 1.1)
    }

    let progress: Double
    let tint: Color
    let geometry: Geometry

    public init(progress: Double, tint: Color = .btAccent, geometry: Geometry = .focus) {
        self.progress = progress
        self.tint = tint
        self.geometry = geometry
    }

    public var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 300
            let cx = size.width / 2, cy = size.height / 2
            let g = geometry
            for i in 0..<g.count {
                let a = Double(i) / Double(g.count) * .pi * 2 - .pi / 2
                let wob = sin(a * 3 + 0.6)
                let r1 = (g.inner + g.innerWobble * wob) * scale
                let r2 = (g.outer + g.outerWobble * wob) * scale
                var line = Path()
                line.move(to: CGPoint(x: cx + r1 * cos(a), y: cy + r1 * sin(a)))
                line.addLine(to: CGPoint(x: cx + r2 * cos(a + g.twist), y: cy + r2 * sin(a + g.twist)))
                let color: Color = Double(i) / Double(g.count) < progress ? tint : (i % 2 == 1 ? .btSubtle : .btSubtleLight)
                context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: g.lineWidth * scale, lineCap: .round))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Deadline tag: accent fill, 11pt bold.
public struct DueTag: View {
    let text: String
    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text)
            .font(.inter(11, .bold))
            .foregroundStyle(Color.btOnAccent)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.btAccent)
    }
}

#Preview("Marks") {
    VStack(alignment: .leading, spacing: 24) {
        TickBar(filled: 19)
        TickBar(count: 40, filled: 14, dashed: 8, height: 14)
        HStack {
            LineRing(progress: 0.25).frame(width: 300)
            LineRing(progress: 0.6, tint: .btBreakGreen, geometry: .compact).frame(width: 220)
        }
        DueTag("HW 6 · 11:59")
    }
    .padding(40)
    .frame(width: 700)
    .background(Color.btGround)
    .onAppear { BTFont.register() }
}
