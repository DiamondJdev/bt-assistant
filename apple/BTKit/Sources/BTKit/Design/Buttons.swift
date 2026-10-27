import SwiftUI

/// Pill buttons. Primary = ink fill, CTA = accent fill, secondary = ink outline.
public struct PillButtonStyle: ButtonStyle {
    public enum Kind { case primary, cta, secondary }
    public enum Size {
        case small, regular, large
        var height: CGFloat { switch self { case .small: 30; case .regular: 36; case .large: 44 } }
        var padding: CGFloat { switch self { case .small: 12; case .regular: 16; case .large: 22 } }
    }

    let kind: Kind
    let size: Size

    public init(_ kind: Kind = .primary, size: Size = .regular) {
        self.kind = kind
        self.size = size
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.inter(13, kind == .cta ? .semibold : .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, size.padding)
            .frame(height: size.height)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(kind == .secondary ? Color.btInk : .clear, lineWidth: 1))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }

    private var fill: Color {
        switch kind {
        case .primary: .btInk
        case .cta: .btAccent
        case .secondary: .clear
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: .btInkOnDark
        case .cta: .btOnAccent
        case .secondary: .btInk
        }
    }
}

public extension ButtonStyle where Self == PillButtonStyle {
    static func pill(_ kind: PillButtonStyle.Kind = .primary, size: PillButtonStyle.Size = .regular) -> PillButtonStyle {
        PillButtonStyle(kind, size: size)
    }
}

/// Uppercase mono text link, e.g. "Open thread →".
public struct MonoLinkStyle: ButtonStyle {
    let color: Color
    public init(color: Color = .btInk) { self.color = color }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .monoLabel(11, tracking: 0.06, color: configuration.isPressed ? .btAccentText : color)
            .contentShape(Rectangle())
    }
}

public extension ButtonStyle where Self == MonoLinkStyle {
    static var monoLink: MonoLinkStyle { MonoLinkStyle() }
    static func monoLink(_ color: Color) -> MonoLinkStyle { MonoLinkStyle(color: color) }
}

#Preview("Buttons") {
    HStack(spacing: 8) {
        Button("Pause") {}.buttonStyle(.pill())
        Button("Book 2:55") {}.buttonStyle(.pill(.cta))
        Button("+5 min") {}.buttonStyle(.pill(.secondary))
        Button("Open thread →") {}.buttonStyle(.monoLink)
    }
    .padding(40)
    .background(Color.btGround)
    .onAppear { BTFont.register() }
}
