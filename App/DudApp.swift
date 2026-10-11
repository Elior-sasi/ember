import SwiftUI
import AppIntents

@main
struct DudApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "he_IL"))
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

/// Siri phrases. Hebrew is the app's development language.
struct DudShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TurnOnHeaterIntent(), phrases: [
            "הדלק את \(.applicationName) ל-\(\.$duration)",
            "תדליק את ה\(.applicationName) ל-\(\.$duration)",
            "הדלק את \(.applicationName)",
            "תדליק את ה\(.applicationName)",
        ], shortTitle: "הדלקת הדוד", systemImageName: "flame")
        AppShortcut(intent: TurnOffHeaterIntent(), phrases: [
            "כבה את \(.applicationName)",
            "תכבה את ה\(.applicationName)",
        ], shortTitle: "כיבוי הדוד", systemImageName: "power")
        AppShortcut(intent: HeaterStatusIntent(), phrases: [
            "מה מצב ה\(.applicationName)",
            "האם ה\(.applicationName) דולק",
        ], shortTitle: "מצב הדוד", systemImageName: "drop")
    }
}
