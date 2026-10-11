import AppIntents
import Foundation

enum HeaterDuration: Int, AppEnum {
    case m15 = 15, m30 = 30, m45 = 45, m60 = 60, m90 = 90, m120 = 120, unlimited = 0

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "זמן חימום"
    static var caseDisplayRepresentations: [HeaterDuration: DisplayRepresentation] = [
        .m15: "15 דקות", .m30: "30 דקות", .m45: "45 דקות", .m60: "שעה",
        .m90: "שעה וחצי", .m120: "שעתיים", .unlimited: "ללא טיימר",
    ]
}

/// These are LiveActivityIntents so that, when tapped in the widget or the Live Activity,
/// they run inside the app's process (which has the home-network permission).
struct TurnOnHeaterIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "הדלקת הדוד"
    static var description = IntentDescription("מדליק את הדוד לזמן שבחרת.")

    @Parameter(title: "זמן", default: .m30)
    var duration: HeaterDuration

    init() {}
    init(duration: HeaterDuration) { self.duration = duration }

    static var parameterSummary: some ParameterSummary { Summary("הדלק את הדוד ל-\(\.$duration)") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let s = try await HeaterController.turnOn(minutes: duration.rawValue)
        if duration == .unlimited {
            return .result(dialog: "הדוד דולק בלי טיימר. הכיבוי האוטומטי יכבה אותו ב-\(s.endsAt.map(Fmt.time) ?? "-").")
        }
        return .result(dialog: "הדוד דולק ל-\(duration.rawValue) דקות, ויכבה ב-\(s.endsAt.map(Fmt.time) ?? "-").")
    }
}

struct TurnOffHeaterIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "כיבוי הדוד"
    static var description = IntentDescription("מכבה את הדוד.")
    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await HeaterController.turnOff()
        return .result(dialog: "הדוד כבוי.")
    }
}

struct AddHeaterTimeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "הוספת זמן לדוד"
    static var description = IntentDescription("מוסיף דקות לחימום שכבר רץ.")

    @Parameter(title: "דקות", default: 15)
    var minutes: Int

    init() {}
    init(minutes: Int) { self.minutes = minutes }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let s = try await HeaterController.addTime(minutes: minutes)
        guard s.state.isOn else { return .result(dialog: "הדוד כבוי, אז אין למה להוסיף זמן.") }
        return .result(dialog: "נוספו \(minutes) דקות. הדוד יכבה ב-\(s.endsAt.map(Fmt.time) ?? "-").")
    }
}

/// The widget's main button: off if on, otherwise on for the widget's minutes.
struct ToggleHeaterIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "הדלקה או כיבוי של הדוד"
    static var isDiscoverable = false
    init() {}

    func perform() async throws -> some IntentResult {
        if Store.shared.snapshot?.state.isOn == true {
            try await HeaterController.turnOff()
        } else {
            try await HeaterController.turnOn(minutes: Store.shared.config.widgetMinutes)
        }
        return .result()
    }
}

struct HeaterStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "מצב הדוד"
    static var description = IntentDescription("אומר אם הדוד דולק ומתי יכבה.")
    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let s = try await HeaterController.refresh()
        if s.state.isOn, let end = s.endsAt {
            let left = Int(end.timeIntervalSinceNow / 60)
            return .result(dialog: "הדוד דולק. נשארו \(left) דקות, והוא יכבה ב-\(Fmt.time(end)).")
        }
        if let last = Store.shared.lastOff {
            return .result(dialog: "הדוד כבוי. הוא כבה \(Fmt.ago(last)).")
        }
        return .result(dialog: "הדוד כבוי.")
    }
}
