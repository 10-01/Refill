// Otis tokens for macOS. Same values as otis.css. Light and dark resolve
// through NSColor's dynamic provider, so views follow the system appearance
// unless the app pins one.
//
// Fonts: bundle Geist and Geist Mono (SIL OFL) and register them in Info.plist
// under "Fonts provided by application". Otis overrides the system look on
// purpose; do not fall back to SF for body text.
//
// Accent is the alarm, not the default fill. Repeating meters use ink;
// orange appears when a value needs attention.

import SwiftUI
import AppKit

enum Otis {

    // MARK: Color

    private static func dynamic(light: String, dark: String) -> Color {
        Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }

    static let paper   = dynamic(light: "#faf9f5", dark: "#1a1814")
    static let ink     = dynamic(light: "#1a1814", dark: "#f0eee5")
    static let ink2    = dynamic(light: "#6b6862", dark: "#a09e96")
    static let ink3    = dynamic(light: "#a09e96", dark: "#6b6862")
    static let line    = dynamic(light: "#e6e3db", dark: "#2a2820")
    static let surface = dynamic(light: "#f3f1eb", dark: "#232017")
    /// Grouped module on paper. One step past surface so panels read without a shadow.
    static let well    = dynamic(light: "#ece8df", dark: "#2c2920")
    /// Backdrop behind an inset workspace window, always past `surface`.
    static let canvas  = dynamic(light: "#e3ddcd", dark: "#100f0c")
    /// Cool field behind a sheet. Not canvas: canvas is warm and reads as linen.
    static let chrome  = dynamic(light: "#e6e9ed", dark: "#161618")
    /// Lifted panel on chrome. White in light so it does not sit cream on tan.
    static let sheet   = dynamic(light: "#ffffff", dark: "#2c2920")
    /// Hairline and meter track on a sheet. `line` sits under `sheet` in dark and vanishes there.
    static let sheetLine = dynamic(light: "#e6e3db", dark: "#3d3a30")

    static let accent       = Color(NSColor(hex: "#ff7a3a"))
    static let accentStrong = Color(NSColor(hex: "#f5610f"))
    /// Orange for text. The accent fails contrast on paper; this sibling passes.
    static let accentText   = dynamic(light: "#c2440a", dark: "#ff7a3a")
    static let accentSoft   = accent.opacity(0.14)

    /// Fill for a repeating meter. Ink is the default. Accent is the alarm.
    static func meterFill(attention: Bool, stale: Bool = false) -> Color {
        if stale { return ink2 }
        return attention ? accent : ink
    }

    /// Figures on a repeating meter. Same size at the call site; color does the work.
    static func meterText(attention: Bool, stale: Bool = false) -> Color {
        if stale { return ink2 }
        return attention ? accentText : ink
    }

    static let ok   = dynamic(light: "#4f8a5b", dark: "#6fae7c")
    static let warn = dynamic(light: "#b8862b", dark: "#d6a05a")
    static let bad  = dynamic(light: "#b5443a", dark: "#d46a5f")

    // MARK: Type

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Geist", size: size).weight(weight)
    }
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Geist Mono", size: size).weight(weight).monospacedDigit()
    }

    static let display = sans(56, weight: .semibold)
    static let h1      = sans(40, weight: .semibold)
    static let h2      = sans(24, weight: .semibold)
    static let reading = sans(17)
    static let ui      = sans(15)
    static let working = sans(13)
    static let label   = mono(11)          // uppercase it at the call site
    static let stat    = mono(24, weight: .medium)

    // MARK: Space and shape

    static let radius: CGFloat = 6
    static let radiusMd: CGFloat = 8
    static let radiusLg: CGFloat = 10
    static let radiusXl: CGFloat = 16
    static let hairline: CGFloat = 1
    static let popoverWidth: CGFloat = 336

    // MARK: Motion

    /// A state change: hover, press, toggle.
    static let fast  = Animation.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.15)
    static let press = Animation.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.06)
    /// A screen change: push, sheet, arrival, an option opening, an illustration filling.
    static let move  = Animation.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.24)
    /// Gap between rows arriving. Eight rows at most take the delay, so arrival ends under 600ms.
    static let stagger: TimeInterval = 0.04
    static let bar   = Animation.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.40)

    /// Reduce motion is a system setting. Honor it: arrival and bar draw skip to their end state.
    static var motionAllowed: Bool {
        !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

extension NSColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(
            srgbRed: CGFloat((v >> 16) & 0xff) / 255,
            green:   CGFloat((v >> 8) & 0xff) / 255,
            blue:    CGFloat(v & 0xff) / 255,
            alpha: 1
        )
    }
}
