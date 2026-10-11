import SwiftUI
import SwitcherKit

/// Same family as "מזגן", warm copper accent for hot water.
enum Theme {
    static let bg = Color(hex: 0x0d0b0a)
    static let surface = Color(hex: 0x17130f)
    static let surface2 = Color(hex: 0x1e1914)
    static let line = Color(hex: 0x2e261f)
    static let fg = Color(hex: 0xf3ece4)
    static let muted = Color(hex: 0x9c8f82)
    static let accent = Color(hex: 0xff9a4d)
    static let accent2 = Color(hex: 0xff6a3d)
    static let ok = Color(hex: 0x5fd39a)
    static let warn = Color(hex: 0xffb454)
    static let bad = Color(hex: 0xff6b6b)
    static let onAccent = Color(hex: 0x1a0c04)
    static let heat = LinearGradient(colors: [accent2, accent], startPoint: .leading, endPoint: .trailing)

    static func num(_ size: CGFloat, _ weight: Font.Weight = .ultraLight) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}

enum Fmt {
    /// 1:05 / 12:30 style, minutes:seconds or hours:minutes
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
