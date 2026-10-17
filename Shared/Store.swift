import Foundation
import SwitcherKit

/// Everything the app and the widget share, kept in the app group.
struct HeaterConfig: Codable, Equatable {
    var host: String = ""
    var deviceID: String = ""
    var deviceKey: String = ""
    var name: String = "דוד"
    var tariff: Double = 0.64          // ₪ per kWh, user-editable
    var widgetMinutes: Int = 30
    var isComplete: Bool { !host.isEmpty && deviceID.count == 6 && deviceKey.count == 2 }
    var client: SwitcherClient { SwitcherClient(host: host, deviceID: deviceID, deviceKey: deviceKey) }
}

/// One heating run, as far as the app could observe it.
struct UsageSession: Codable, Equatable {
    var start: Date
    var end: Date
    var watts: Int
    var minutes: Double { end.timeIntervalSince(start) / 60 }
    var kWh: Double { Double(watts) * end.timeIntervalSince(start) / 3_600_000 }
}

/// A schedule the user switched off. The heater has no "disabled" flag we can rely on,
/// so a disabled schedule is removed from the heater and kept here until switched back on.
struct ParkedSchedule: Codable, Equatable, Identifiable {
    var id = UUID()
    var weekdays: UInt8
    var startMinutes: Int
    var endMinutes: Int
}

struct Snapshot: Codable, Equatable {
    var state: HeaterState
    var at: Date
    /// When the heater will switch itself off (timer or auto-shutdown), if on.
    var endsAt: Date? { state.isOn ? at.addingTimeInterval(TimeInterval(state.secondsLeft)) : nil }
    var startedAt: Date? { state.isOn ? at.addingTimeInterval(-TimeInterval(state.secondsOn)) : nil }
}

final class Store {
    static let shared = Store()
    static let appGroup = "group.com.elior.dud"
    let defaults: UserDefaults

    init() { defaults = UserDefaults(suiteName: Store.appGroup) ?? .standard }

    var config: HeaterConfig {
        get { load("config") ?? HeaterConfig() }
        set { save(newValue, "config") }
    }
    var snapshot: Snapshot? {
        get { load("snapshot") }
        set { save(newValue, "snapshot") }
    }
    /// Whether the current run was started without a timer.
    var unlimitedRun: Bool {
        get { defaults.bool(forKey: "unlimited") }
        set { defaults.set(newValue, forKey: "unlimited") }
    }
    var sessions: [UsageSession] {
        get { load("sessions") ?? [] }
        set { save(Array(newValue.suffix(500)), "sessions") }
    }
    var openSession: UsageSession? {
        get { load("open") }
        set { save(newValue, "open") }
    }
    var parked: [ParkedSchedule] {
        get { load("parked") ?? [] }
        set { save(newValue, "parked") }
    }
    /// "The water is hot" notification on or off (on by default).
    var notifyWhenDone: Bool {
        get { defaults.object(forKey: "notify") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "notify") }
    }
    /// Last schedule list read from the heater, for the widget.
    var cachedSchedules: [HeaterSchedule] {
        get { load("schedules") ?? [] }
        set { save(newValue, "schedules") }
    }
    var lastOff: Date? {
        get { defaults.object(forKey: "lastOff") as? Date }
        set { defaults.set(newValue, forKey: "lastOff") }
    }

    private func load<T: Decodable>(_ key: String) -> T? {
        guard let d = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }
    private func save<T: Encodable>(_ value: T?, _ key: String) {
        guard let value else { defaults.removeObject(forKey: key); return }
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    /// Keeps the usage log in step with what the heater reports.
    func record(_ s: Snapshot) {
        if s.state.isOn, let started = s.startedAt {
            var open = openSession ?? UsageSession(start: started, end: s.at, watts: s.state.powerWatts)
            // a new run began since we last looked
            if abs(open.start.timeIntervalSince(started)) > 120 {
                close(open)
                open = UsageSession(start: started, end: s.at, watts: s.state.powerWatts)
            }
            open.end = s.at
            if s.state.powerWatts > 0 { open.watts = s.state.powerWatts }
            openSession = open
        } else if let open = openSession {
            // it turned off while we weren't looking: assume it ran to its planned end
            var done = open
            if let prev = snapshot, let planned = prev.endsAt, planned < s.at { done.end = max(done.end, planned) }
            else { done.end = max(done.end, min(s.at, done.end.addingTimeInterval(60))) }
            close(done)
            openSession = nil
            lastOff = done.end
        }
        snapshot = s
    }

    private func close(_ s: UsageSession) {
        guard s.minutes >= 1 else { return }
        var all = sessions
        all.append(s)
        sessions = all
    }

    var lastSession: UsageSession? { sessions.last }

    /// The schedule that starts soonest from `now`, with its start date.
    static func nextRun(_ list: [HeaterSchedule], now: Date = Date()) -> (schedule: HeaterSchedule, at: Date)? {
        let cal = Calendar.current
        let today = cal.component(.weekday, from: now) - 1     // 0 = Sunday
        let mins = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        var best: (HeaterSchedule, Int)?
        for s in list {
            let days = s.weekdays == 0 ? [today] : Array(WeekdayBits.indices(s.weekdays))
            for d in days {
                var delta = ((d - today) + 7) % 7 * 1440 + s.startMinutes - mins
                if delta < 0 { delta += 7 * 1440 }
                if s.weekdays == 0 && delta >= 1440 { continue }   // a one-off that already passed today
                if best == nil || delta < best!.1 { best = (s, delta) }
            }
        }
        guard let best else { return nil }
        let raw = now.addingTimeInterval(TimeInterval(best.1 * 60)).timeIntervalSince1970
        let at = Date(timeIntervalSince1970: (raw / 60).rounded(.down) * 60)
        return (best.0, at)
    }
}
