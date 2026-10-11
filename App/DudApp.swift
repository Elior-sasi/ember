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
                .tint(Theme.accent)
        }
    }
}

/// Siri phrases. Hebrew is the app's development language, and every phrase must name the app.
struct DudShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TurnOnHeaterIntent(), phrases: [
            "הדלק את הדוד ב\(.applicationName) ל-\(\.$duration)",
            "\(.applicationName) הדלק את הדוד ל-\(\.$duration)",
            "תדליק את הדוד ב\(.applicationName) ל-\(\.$duration)",
            "הדלק את הדוד ב\(.applicationName)",
            "\(.applicationName) הדלק את הדוד",
        ], shortTitle: "הדלקת הדוד", systemImageName: "flame")
        AppShortcut(intent: TurnOffHeaterIntent(), phrases: [
            "כבה את הדוד ב\(.applicationName)",
            "\(.applicationName) כבה את הדוד",
            "תכבה את הדוד ב\(.applicationName)",
        ], shortTitle: "כיבוי הדוד", systemImageName: "power")
        AppShortcut(intent: HeaterStatusIntent(), phrases: [
            "מה מצב הדוד ב\(.applicationName)",
            "האם הדוד דולק ב\(.applicationName)",
        ], shortTitle: "מצב הדוד", systemImageName: "drop")
    }
}
