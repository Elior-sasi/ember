import SwiftUI
import AppIntents

@main
struct DudApp: App {
    @StateObject private var model = AppModel()

    init() { HomeGeo.shared.start() }

    var body: some Scene {
        WindowGroup {
            HomeOnRoot()
                .environmentObject(model)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "he_IL"))
                .tint(Theme.home)
                .onOpenURL { model.handleLink($0) }
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
        AppShortcut(intent: TVPowerIntent(), phrases: [
            "תדליק את הטלוויזיה ב\(.applicationName)",
            "תכבה את הטלוויזיה ב\(.applicationName)",
            "\(.applicationName) טלוויזיה",
        ], shortTitle: "טלוויזיה", systemImageName: "tv")
        AppShortcut(intent: TVOpenAppIntent(), phrases: [
            "תפתח את \(\.$app) בטלוויזיה ב\(.applicationName)",
            "\(.applicationName) תפתח \(\.$app)",
        ], shortTitle: "אפליקציה בטלוויזיה", systemImageName: "play.tv")
        AppShortcut(intent: DeviceOnIntent(), phrases: [
            "תדליק את \(\.$device) ב\(.applicationName)",
            "הדלק את \(\.$device) ב\(.applicationName)",
            "\(.applicationName) תדליק \(\.$device)",
        ], shortTitle: "הדלקת מכשיר", systemImageName: "power.circle.fill")
        AppShortcut(intent: DeviceOffIntent(), phrases: [
            "תכבה את \(\.$device) ב\(.applicationName)",
            "כבה את \(\.$device) ב\(.applicationName)",
            "\(.applicationName) תכבה \(\.$device)",
        ], shortTitle: "כיבוי מכשיר", systemImageName: "power.circle")
        AppShortcut(intent: RunSceneIntent(), phrases: [
            "תפעיל \(\.$scene) ב\(.applicationName)",
            "\(.applicationName) \(\.$scene)",
        ], shortTitle: "סצנה", systemImageName: "sparkles")
        AppShortcut(intent: HeaterStatusIntent(), phrases: [
            "מה מצב הדוד ב\(.applicationName)",
            "האם הדוד דולק ב\(.applicationName)",
        ], shortTitle: "מצב הדוד", systemImageName: "drop")
    }
}
