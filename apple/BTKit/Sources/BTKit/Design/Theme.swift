import CoreText
import SwiftUI

/// Sand Grid color tokens from design/HANDOFF.md.
public extension Color {
    static let btGround = Color(hex: 0xE9DFD3)
    static let btGroundDeep = Color(hex: 0xDCD0C2)
    static let btPaper = Color(hex: 0xF4EDE4)
    static let btInk = Color(hex: 0x2E2218)
    static let btInkOnDark = Color(hex: 0xF4EDE4)
    static let btMuted = Color(hex: 0x6B5C4C)
    static let btSubtle = Color(hex: 0x8C7E70)
    /// Alternate unfilled LineRing segment.
    static let btSubtleLight = Color(hex: 0xB3A595)
    static let btLine = Color(hex: 0xB5A796)
    static let btRule = Color(hex: 0xD6C9B9)
    static let btTrack = Color(hex: 0xCDBFAE)
    static let btFillClass = Color(hex: 0xDCCFBF)
    static let btAccent = Color(hex: 0xD9531E)
    static let btAccentText = Color(hex: 0xB8431A)
    static let btAccentDeep = Color(hex: 0x8A3412)
    static let btAccentTint = Color(hex: 0xD9531E).opacity(0.08)
    static let btDraftFill = Color(hex: 0xF7E4D8)
    static let btOnAccent = Color(hex: 0x1F120A)
    static let btBreakGreen = Color(hex: 0x2E6B4F)

    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

public enum BTFont {
    static let interTight = "Inter Tight"
    static let geistMono = "Geist Mono"

    /// Registers the bundled fonts once. Call before the first view draws.
    @MainActor public static func register() {
        guard !registered else { return }
        registered = true
        for name in ["InterTight", "GeistMono"] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    @MainActor private static var registered = false
}

public extension Font {
    /// Inter Tight: UI and display.
    static func inter(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(BTFont.interTight, fixedSize: size).weight(weight)
    }

    /// Geist Mono: labels, times, numbers.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(BTFont.geistMono, fixedSize: size).weight(weight)
    }
}

public extension View {
    /// Inter Tight with tracking given in em, like the CSS in the mockups.
    func interStyle(_ size: CGFloat, _ weight: Font.Weight = .regular, tracking em: CGFloat = 0) -> some View {
        font(.inter(size, weight)).tracking(size * em)
    }

    /// Uppercase Geist Mono label. Defaults match the "cell label" style: 11pt, +0.08em, muted.
    func monoLabel(_ size: CGFloat = 11, _ weight: Font.Weight = .regular, tracking em: CGFloat = 0.08, color: Color = .btMuted) -> some View {
        font(.mono(size, weight)).tracking(size * em).textCase(.uppercase).foregroundStyle(color)
    }
}

/// Shared spacing constants.
public enum BTMetrics {
    public static let cellPadding: CGFloat = 20
    public static let headerHeight: CGFloat = 52
    public static let minContentWidth: CGFloat = 1100
    public static let dash: [CGFloat] = [3, 3]
}
