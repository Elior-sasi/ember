import SwiftUI
import SwitcherKit

/// Ember: the same glass look as Breeze, with a copper accent for hot water.
/// Colors adapt to light and dark mode like Breeze does.
enum Theme {
    static let bg = Color(light: 0xf2f2f7, dark: 0x000000)
    static let fg = Color(light: 0x000000, dark: 0xffffff)
    static let muted = Color(lightRGBA: (60, 60, 67, 0.6), darkRGBA: (235, 235, 245, 0.6))
    static let line = Color(lightRGBA: (60, 60, 67, 0.14), darkRGBA: (255, 255, 255, 0.12))
    static let glass = Color(lightRGBA: (255, 255, 255, 0.72), darkRGBA: (255, 255, 255, 0.075))
    static let glass2 = Color(lightRGBA: (255, 255, 255, 0.85), darkRGBA: (255, 255, 255, 0.11))
    static let glassEdge = Color(lightRGBA: (0, 0, 0, 0.07), darkRGBA: (255, 255, 255, 0.16))
    static let glassHi = Color(lightRGBA: (255, 255, 255, 1), darkRGBA: (255, 255, 255, 0.22))
    static let fill = Color(light: 0xffffff, dark: 0x1c1c1e)
    static let fill2 = Color(light: 0xe9e9ee, dark: 0x2c2c2e)
    /// accent mixed 22% into the fills, for selected controls
    static let accentFill = Color(light: 0xffe4cf, dark: 0x4a3222)
    static let accentFill2 = Color(light: 0xf6dbc6, dark: 0x543a2a)
    static let track = Color(lightRGBA: (0, 0, 0, 0.08), darkRGBA: (255, 255, 255, 0.1))

    static let accent = Color(hex: 0xff9a4d)
    static let accent2 = Color(hex: 0xff6a3d)
    /// accent for text and icons - darker in light mode so it stays readable
    static let accentInk = Color(light: 0xb9500f, dark: 0xff9a4d)
    static let accentSoft = Color(hex: 0xff8c3c).opacity(0.18)
    static let onAccent = Color(hex: 0x1a0c04)
    static let ok = Color(hex: 0x34c759)
    static let warn = Color(hex: 0xffb454)
    static let bad = Color(hex: 0xff6b6b)
    static let heat = LinearGradient(colors: [accent2, accent], startPoint: .leading, endPoint: .trailing)

    // kept for the widget and Live Activity, which always sit on a dark surface
    static let surface = Color(hex: 0x17130f)
    static let surface2 = Color(hex: 0x1e1914)

    static func num(_ size: CGFloat, _ weight: Font.Weight = .ultraLight) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
    init(lightRGBA l: (Int, Int, Int, Double), darkRGBA d: (Int, Int, Int, Double)) {
        self.init(UIColor { t in
            let c = t.userInterfaceStyle == .dark ? d : l
            return UIColor(red: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255, blue: CGFloat(c.2) / 255, alpha: CGFloat(c.3))
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}

/// Breeze 6.0 "calm": solid fills for controls, glass only on floating layers (bar, sheets, toast).
struct Card: ViewModifier {
    var radius: CGFloat
    var selected = false
    var inner = false       // inside a sheet or the details panel: one shade lighter
    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(selected ? (inner ? Theme.accentFill2 : Theme.accentFill) : (inner ? Theme.fill2 : Theme.fill))
        }
    }
}

extension View {
    func card(_ radius: CGFloat = 22, selected: Bool = false, inner: Bool = false) -> some View {
        modifier(Card(radius: radius, selected: selected, inner: inner))
    }
}

enum Fmt {
    /// 1:05 / 12:30 style, minutes:seconds or hours:minutes:seconds
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
    static func hm(_ minutes: Int) -> String { String(format: "%d:%02d", minutes / 60, minutes % 60) }
    static func time(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "he_IL"); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
    static func ago(_ d: Date, now: Date = Date()) -> String {
        let m = Int(now.timeIntervalSince(d) / 60)
        if m < 1 { return "עכשיו" }
        if m < 60 { return "לפני \(m) דק׳" }
        if m < 60 * 24 { return "לפני \(m / 60) שע׳" }
        return "לפני \(m / 1440) ימים"
    }
    static let dayLetters = ["א׳", "ב׳", "ג׳", "ד׳", "ה׳", "ו׳", "ש׳"]
    static func days(_ mask: UInt8) -> String {
        if mask == 0 { return "פעם אחת" }
        let idx = WeekdayBits.indices(mask).sorted()
        if idx.count == 7 { return "כל יום" }
        if idx == [0, 1, 2, 3, 4] { return "א׳-ה׳" }
        return idx.map { dayLetters[$0] }.joined(separator: " ")
    }
}
