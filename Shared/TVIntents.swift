import AppIntents
import ActivityKit
import Foundation

enum TVKey: String, AppEnum {
    case power, playPause, volumeUp, volumeDown, mute, home, back
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "מקש בשלט"
    static var caseDisplayRepresentations: [TVKey: DisplayRepresentation] = [
        .power: "הדלקה/כיבוי", .playPause: "הפעלה/השהיה", .volumeUp: "הגברה", .volumeDown: "הנמכה",
        .mute: "השתקה", .home: "מסך הבית", .back: "חזרה",
    ]
    var code: Int {
        switch self {
        case .power: return 26
        case .playPause: return 85
        case .volumeUp: return 24
        case .volumeDown: return 25
        case .mute: return 164
        case .home: return 3
        case .back: return 4
        }
    }
}

enum TVApp: String, AppEnum {
    case youtube, netflix, disney, prime, spotify, appletv
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "אפליקציה בטלוויזיה"
    static var caseDisplayRepresentations: [TVApp: DisplayRepresentation] = [
        .youtube: "יוטיוב", .netflix: "נטפליקס", .disney: "דיסני+", .prime: "פריים וידאו", .spotify: "ספוטיפיי", .appletv: "Apple TV",
    ]
    var link: String {
        switch self {
        case .youtube: return "https://www.youtube.com"
        case .netflix: return "https://www.netflix.com/title"
        case .disney: return "https://www.disneyplus.com"
        case .prime: return "https://app.primevideo.com"
        case .spotify: return "spotify://"
        case .appletv: return "https://tv.apple.com"
        }
    }
}

/// LiveActivityIntents run inside the app (which may use the home network), also from the lock screen and Control Center.
struct TVKeyIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "מקש בשלט של הטלוויזיה"
    static var isDiscoverable = false
    @Parameter(title: "מקש") var key: TVKey
    init() {}
    init(_ k: TVKey) { key = k }
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        try await TVRemote.shared.key(key.code)
        #endif
        return .result()
    }
}

struct TVPowerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "הדלקה או כיבוי של הטלוויזיה"
    static var description = IntentDescription("מדליק או מכבה את Google TV.")
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if !WIDGET_EXTENSION
        try await TVRemote.shared.key(26)
        #endif
        return .result(dialog: "בוצע")
    }
}

struct TVOpenAppIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "פתיחת אפליקציה בטלוויזיה"
    static var description = IntentDescription("פותח אפליקציה ב-Google TV.")
    @Parameter(title: "אפליקציה", default: .netflix) var app: TVApp
    init() {}
    init(_ a: TVApp) { app = a }
    static var parameterSummary: some ParameterSummary { Summary("פתח את \(\.$app) בטלוויזיה") }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if !WIDGET_EXTENSION
        try await TVRemote.shared.app(app.link)
        #endif
        return .result(dialog: "נפתח בטלוויזיה")
    }
}

struct TVActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var on: Bool
        var app: String
    }
    var name: String
}
