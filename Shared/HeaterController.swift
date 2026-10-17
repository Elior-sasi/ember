import Foundation
import Network
import SwitcherKit
import WidgetKit
import UserNotifications
#if canImport(ActivityKit)
import ActivityKit
#endif

enum HeaterProblem: Error, LocalizedError {
    case notSetUp, away, noAnswer
    var errorDescription: String? {
        switch self {
        case .notSetUp: return "הדוד עוד לא מוגדר. פתח את האפליקציה כדי להגדיר אותו."
        case .away: return "אתה לא מחובר ל-WiFi של הבית, אז הדוד לא זמין."
        case .noAnswer: return "הדוד לא עונה. בדוק שהוא מחובר ל-WiFi ושהכתובת שלו לא השתנתה."
        }
    }
}

/// Every command goes through here so the app, the widget, Siri and the
/// Live Activity all stay in step.
enum HeaterController {
    static var store: Store { .shared }

    @discardableResult
    static func refresh() async throws -> Snapshot {
        let c = try client()
        let s = try await run { try await c.state() }
        return publish(s)
    }

    /// minutes = 0 means no timer.
    @discardableResult
    static func turnOn(minutes: Int) async throws -> Snapshot {
        let c = try client()
        try await run { try await c.turnOn(minutes: minutes) }
        store.unlimitedRun = minutes == 0
        return try await refreshAfterCommand(c)
    }

    @discardableResult
    static func turnOff() async throws -> Snapshot {
        let c = try client()
        try await run { try await c.turnOff() }
        store.unlimitedRun = false
        return try await refreshAfterCommand(c)
    }

    /// Restarts the timer with the time that was left plus `minutes` (which may be negative).
    @discardableResult
    static func addTime(minutes: Int) async throws -> Snapshot {
        let c = try client()
        let now = try await run { try await c.state() }
        guard now.isOn, !store.unlimitedRun else { return publish(now) }
        let total = max(1, Int((Double(now.secondsLeft) / 60).rounded(.up)) + minutes)
        try await run { try await c.turnOn(minutes: total) }
        return try await refreshAfterCommand(c)
    }

    static func setAutoShutdown(minutes: Int) async throws {
        let c = try client()
        try await run { try await c.setAutoShutdown(minutes: minutes) }
        _ = try? await refresh()
    }

    // MARK: schedules

    static func schedules() async throws -> [HeaterSchedule] {
        let c = try client()
        return try await run { try await c.schedules() }
    }
    static func addSchedule(weekdays: UInt8, start: Int, end: Int) async throws {
        let c = try client()
        try await run { try await c.createSchedule(weekdays: weekdays, startMinutes: start, endMinutes: end) }
    }
    static func deleteSchedule(slot: Int) async throws {
        let c = try client()
        try await run { try await c.deleteSchedule(slot: slot) }
    }

    // MARK: plumbing

    static func client() throws -> SwitcherClient {
        let cfg = store.config
        guard cfg.isComplete else { throw HeaterProblem.notSetUp }
        return cfg.client
    }

    /// Runs a heater call and turns network failures into something a person can act on.
    static func run<T>(_ op: () async throws -> T) async throws -> T {
        do { return try await op() }
        catch is SwitcherError {
            if await NetWatch.isOnWiFi() == false { throw HeaterProblem.away }
            throw HeaterProblem.noAnswer
        }
    }

    private static func refreshAfterCommand(_ c: SwitcherClient) async throws -> Snapshot {
        // the heater needs a moment before its report reflects the command
        try? await Task.sleep(nanoseconds: 600_000_000)
        let s = try await run { try await c.state() }
        return publish(s)
    }

    @discardableResult
    static func publish(_ state: HeaterState) -> Snapshot {
        let snap = Snapshot(state: state, at: Date())
        store.record(snap)
        if !state.isOn { store.unlimitedRun = false }
        WidgetCenter.shared.reloadAllTimelines()
        Notifier.sync(snap, unlimited: store.unlimitedRun, name: store.config.name)
        LiveActivityManager.sync(snap, unlimited: store.unlimitedRun, name: store.config.name)
        return snap
    }
}

// MARK: - network

enum NetWatch {
    /// nil when it can't tell in time.
    static func isOnWiFi() async -> Bool? {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool?, Never>) in
            let monitor = NWPathMonitor()
            let once = OnceFlag()
            monitor.pathUpdateHandler = { path in
                if once.claim() {
                    monitor.cancel()
                    cont.resume(returning: path.status == .satisfied && path.usesInterfaceType(.wifi))
                }
            }
            let q = DispatchQueue(label: "netwatch")
            monitor.start(queue: q)
            q.asyncAfter(deadline: .now() + 1) {
                if once.claim() { monitor.cancel(); cont.resume(returning: nil) }
            }
        }
    }
}

final class OnceFlag: @unchecked Sendable {
    private var used = false
    private let lock = NSLock()
    func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if used { return false }; used = true; return true }
}

// MARK: - "the water is hot" notification

enum Notifier {
    static let id = "heating-done"

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func sync(_ snap: Snapshot, unlimited: Bool, name: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard Store.shared.notifyWhenDone, let end = snap.endsAt, end.timeIntervalSinceNow > 5 else { return }
        let content = UNMutableNotificationContent()
        let minutes = Int(((snap.startedAt.map { end.timeIntervalSince($0) } ?? 0) / 60).rounded())
        if unlimited {
            content.title = "ה\(name) כבה"
            content.body = "הכיבוי האוטומטי כיבה אותו אחרי \(Fmt.hm(minutes)) שעות."
        } else {
            content.title = "המים חמים"
            content.body = "ה\(name) חימם \(minutes) דקות וכבה. אפשר להתקלח."
        }
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: end.timeIntervalSinceNow, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}

// MARK: - Live Activity

enum LiveActivityManager {
    static func sync(_ snap: Snapshot, unlimited: Bool, name: String) {
        // Live Activities can only be started by the app itself. Intents that run from the
        // widget are LiveActivityIntents, so they execute in the app process anyway.
        #if canImport(ActivityKit) && os(iOS) && !WIDGET_EXTENSION
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let current = Activity<HeaterActivityAttributes>.activities
        if let end = snap.endsAt, let start = snap.startedAt {
            let state = HeaterActivityAttributes.ContentState(startedAt: start, endsAt: end, unlimited: unlimited, watts: snap.state.powerWatts)
            let content = ActivityContent(state: state, staleDate: end.addingTimeInterval(60))
            if let a = current.first {
                Task { await a.update(content) }
            } else {
                _ = try? Activity.request(attributes: HeaterActivityAttributes(name: name), content: content, pushType: nil)
            }
        } else {
            for a in current {
                Task { await a.end(nil, dismissalPolicy: .immediate) }
            }
        }
        #endif
    }
}
