import SwiftUI

/// One clause of a BT sentence.
public struct Clause: Sendable {
    public enum Tone: Sendable { case ink, muted, accent }
    public var text: String
    public var tone: Tone

    public init(_ text: String, _ tone: Tone = .ink) {
        self.text = text
        self.tone = tone
    }

    var color: Color {
        switch tone {
        case .ink: .btInk
        case .muted: .btMuted
        case .accent: .btAccentText
        }
    }
}

/// A sentence in ink / muted / accentText tones. Join clauses with the spaces you want.
public func toned(_ clauses: [Clause]) -> Text {
    clauses.reduce(Text("")) { $0 + Text($1.text).foregroundStyle($1.color) }
}

/// Mono "BT · …" label, a 24–30pt sentence in three tones, then pill actions.
public struct BTStatement<Actions: View>: View {
    let label: String
    let meta: String?
    let clauses: [Clause]
    let size: CGFloat
    let actions: Actions

    public init(
        label: String, meta: String? = nil, clauses: [Clause], size: CGFloat = 30,
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.label = label
        self.meta = meta
        self.clauses = clauses
        self.size = size
        self.actions = actions()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(label).monoLabel()
                Spacer()
                if let meta { Text(meta).monoLabel() }
            }
            Spacer(minLength: 0)
            toned(clauses)
                .font(.inter(size, .medium))
                .tracking(size * -0.025)
                .lineSpacing(size * 0.08)
                .frame(maxWidth: 620, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) { actions }
        }
    }
}

/// Paper card for one BT write: "CALENDAR · MOVED", a title, a mono detail and an optional link.
/// Undone cards get a dashed border, 60% opacity and strikethrough.
public struct BTResultCardView: View {
    let card: ResultCard
    let open: ((DeepLink) -> Void)?

    public init(_ card: ResultCard, open: ((DeepLink) -> Void)? = nil) {
        self.card = card
        self.open = open
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(kindLabel).monoLabel(10, color: card.isUndone ? .btMuted : .btAccentText)
            Text(card.title)
                .font(.inter(15, .semibold))
                .strikethrough(card.isUndone)
            Text(card.detail)
                .font(.mono(11))
                .foregroundStyle(Color.btMuted)
                .strikethrough(card.isUndone)
            if card.isUndone {
                Text("Undone").monoLabel(10)
            } else if let link = card.deepLink, let open {
                Button(linkLabel(link)) { open(link) }.buttonStyle(.monoLink)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.btPaper)
        .overlay(
            Rectangle().strokeBorder(
                Color.btInk,
                style: StrokeStyle(lineWidth: 1, dash: card.isUndone ? BTMetrics.dash : [])
            )
        )
        .opacity(card.isUndone ? 0.6 : 1)
        .foregroundStyle(Color.btInk)
    }

    private var kindLabel: String {
        let kind = card.kind == .todo ? "To-do" : card.kind.rawValue
        return "\(kind) · \(card.verb.rawValue)"
    }

    private func linkLabel(_ link: DeepLink) -> String {
        switch link {
        case .today: "Open Today →"
        case .focus: "Open Focus →"
        case .calendar(.day, _, _): "Open day →"
        case .calendar(.week, _, _): "Open week →"
        case .calendar(.month, _, _): "Open month →"
        case .code: "Roadmap →"
        case .bt: "Open thread →"
        }
    }
}

/// Square paper card with a 1px ink border and the hard offset shadow. Use for popovers.
public struct PaperCard<Content: View>: View {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        content
            .padding(16)
            .background(Color.btPaper)
            .overlay(Rectangle().strokeBorder(Color.btInk, lineWidth: 1))
            .background(Color.btInk.opacity(0.12).offset(x: 8, y: 8))
    }
}

/// A calendar block, styled by kind.
public struct EventBlockView: View {
    let title: String
    let detail: String?
    let kind: EventKind
    let isSelected: Bool

    public init(title: String, detail: String? = nil, kind: EventKind, isSelected: Bool = false) {
        self.title = title
        self.detail = detail
        self.kind = kind
        self.isSelected = isSelected
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.inter(12, .semibold)).lineLimit(2)
            if let detail { Text(detail).font(.mono(10)).opacity(0.8).lineLimit(1) }
        }
        .foregroundStyle(Self.foreground(kind))
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Self.fill(kind))
        .overlay(border)
        .overlay(isSelected ? Rectangle().stroke(Color.btAccent, lineWidth: 3).padding(-1.5) : nil)
        .clipped()
    }

    @ViewBuilder private var border: some View {
        switch kind {
        case .work:
            Rectangle().strokeBorder(Color.btSubtle, lineWidth: 1)
        case .studyPlanned:
            Rectangle().strokeBorder(Color.btInk, style: StrokeStyle(lineWidth: 1.5, dash: BTMetrics.dash))
        case .btDraft:
            Rectangle().strokeBorder(Color.btAccent, style: StrokeStyle(lineWidth: 1.5, dash: BTMetrics.dash))
        case .classSession, .focusLogged, .deadline:
            EmptyView()
        }
    }

    public static func fill(_ kind: EventKind) -> Color {
        switch kind {
        case .classSession: .btFillClass
        case .work: .btGround
        case .focusLogged: .btInk
        case .studyPlanned: .btPaper
        case .btDraft: .btDraftFill
        case .deadline: .btAccent
        }
    }

    public static func foreground(_ kind: EventKind) -> Color {
        switch kind {
        case .focusLogged: .btInkOnDark
        case .btDraft: .btAccentDeep
        case .deadline: .btOnAccent
        default: .btInk
        }
    }
}

#Preview("BT views") {
    VStack(alignment: .leading, spacing: 24) {
        BTStatement(
            label: "BT · read 3 modules", meta: "12:45",
            clauses: [
                Clause("You have 44 minutes before Discrete Math. "),
                Clause("Finish the sync tests, stop at 1:20, and I’ll put ", .muted),
                Clause("session 3 at 2:55.", .accent),
            ]
        ) {
            Button("Book 2:55") {}.buttonStyle(.pill(.cta))
            Button("Reply") {}.buttonStyle(.pill(.secondary))
        }
        HStack(alignment: .top) {
            BTResultCardView(ResultCard(kind: .calendar, verb: .moved, title: "Discrete HW 6", detail: "2:55 → 5:15 – 6:05", deepLink: .calendar(.day)), open: { _ in })
            BTResultCardView(ResultCard(kind: .memory, verb: .saved, title: "TA office hours", detail: "Fri 10–11", isUndone: true))
        }
        HStack(spacing: 8) {
            ForEach(EventKind.allCases, id: \.self) { kind in
                EventBlockView(title: kind.rawValue, detail: "2:55", kind: kind, isSelected: kind == .studyPlanned)
                    .frame(width: 110, height: 60)
            }
        }
        PaperCard { Text("Popover") }
    }
    .padding(40)
    .frame(width: 900)
    .background(Color.btGround)
    .foregroundStyle(Color.btInk)
    .onAppear { BTFont.register() }
}
