import ActivityKit
import CoreLocation
import Foundation
import UIKit
import UserNotifications
import WidgetKit

/// Leaving / coming home, by the iPhone itself (no Shortcuts setup).
/// iOS wakes the app when it crosses the circle around home, even if the app is closed.
@MainActor
final class HomeGeo: NSObject, CLLocationManagerDelegate {
    static let shared = HomeGeo()
    private let lm = CLLocationManager()
    private var waitLoc: CheckedContinuation<CLLocation, Error>?
    private var waitAuth: CheckedContinuation<Void, Never>?
    private let d = HomeLink.defaults

    var lat: Double? { d.object(forKey: "geo.lat") as? Double }
    var lon: Double? { d.object(forKey: "geo.lon") as? Double }
    var radius: Double { (d.object(forKey: "geo.r") as? Double) ?? 150 }
    var enabled: Bool { d.bool(forKey: "geo.on") }

    override init() {
        super.init()
        lm.delegate = self
    }
    /// Called at launch, so a wake-up from a region event reaches the delegate.
    func start() { _ = lm.authorizationStatus }

    var authText: String {
        switch lm.authorizationStatus {
        case .authorizedAlways: return "always"
        case .authorizedWhenInUse: return "inuse"
        case .denied, .restricted: return "denied"
        default: return "none"
        }
    }

    func state() -> [String: Any] {
        var o: [String: Any] = ["ok": true, "on": enabled && !lm.monitoredRegions.isEmpty, "auth": authText, "radius": radius,
                                "hasHome": lat != nil, "last": d.string(forKey: "geo.last") ?? ""]
        if let lat, let lon { o["lat"] = lat; o["lon"] = lon }
        return o
    }

    private func askAuth(always: Bool) async {
        let s = lm.authorizationStatus
        if s == .authorizedAlways || s == .denied || s == .restricted { return }
        if s == .authorizedWhenInUse && !always { return }
        await withCheckedContinuation { c in
            waitAuth = c
            if s == .notDetermined { lm.requestWhenInUseAuthorization() } else { lm.requestAlwaysAuthorization() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.waitAuth?.resume(); self?.waitAuth = nil }
        }
        // iOS often grants "Always" provisionally without a callback (it asks later, at the first region event),
        // so ask and move on instead of waiting up to 30 seconds for an answer that may not come now.
        if always && lm.authorizationStatus == .authorizedWhenInUse { lm.requestAlwaysAuthorization() }
    }

    /// "I'm home now": remembers the current location as home.
    func setHere() async throws -> [String: Any] {
        await askAuth(always: false)
        guard lm.authorizationStatus == .authorizedWhenInUse || lm.authorizationStatus == .authorizedAlways else {
            throw HomeLink.Failure.server("צריך לאשר מיקום בהגדרות של האייפון")
        }
        lm.desiredAccuracy = kCLLocationAccuracyBest
        let loc: CLLocation = try await withCheckedThrowingContinuation { c in
            waitLoc?.resume(throwing: HomeLink.Failure.server("בקשת מיקום חדשה"))
            waitLoc = c
            lm.requestLocation()
        }
        d.set(loc.coordinate.latitude, forKey: "geo.lat")
        d.set(loc.coordinate.longitude, forKey: "geo.lon")
        if enabled { monitor() }
        return state()
    }

    func enable(leave: String, arrive: String, radius r: Double?) async throws -> [String: Any] {
        guard lat != nil else { throw HomeLink.Failure.server("קודם צריך לסמן איפה הבית") }
        d.set(leave, forKey: "geo.leave")
        d.set(arrive, forKey: "geo.arrive")
        if let r { d.set(max(100, min(1000, r)), forKey: "geo.r") }
        d.set(true, forKey: "geo.on")
        await askAuth(always: true)
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        monitor()
        return state()
    }

    func links(leave: String, arrive: String) {
        d.set(leave, forKey: "geo.leave")
        d.set(arrive, forKey: "geo.arrive")
    }

    func disable() -> [String: Any] {
        d.set(false, forKey: "geo.on")
        lm.monitoredRegions.forEach { lm.stopMonitoring(for: $0) }
        return state()
    }

    private func monitor() {
        lm.monitoredRegions.forEach { lm.stopMonitoring(for: $0) }
        guard enabled, let lat, let lon else { return }
        let reg = CLCircularRegion(center: CLLocationCoordinate2D(latitude: lat, longitude: lon), radius: radius, identifier: "home")
        reg.notifyOnEntry = true
        reg.notifyOnExit = true
        lm.startMonitoring(for: reg)
    }

    // MARK: delegate
    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        Task { @MainActor in self.waitAuth?.resume(); self.waitAuth = nil }
    }
    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let l = locs.last else { return }
        Task { @MainActor in self.waitLoc?.resume(returning: l); self.waitLoc = nil }
    }
    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.waitLoc?.resume(throwing: HomeLink.Failure.server("לא הצלחתי לקבל מיקום")); self.waitLoc = nil }
    }
    nonisolated func locationManager(_ m: CLLocationManager, didEnterRegion region: CLRegion) {
        Task { @MainActor in await self.fire(arrive: true) }
    }
    nonisolated func locationManager(_ m: CLLocationManager, didExitRegion region: CLRegion) {
        Task { @MainActor in await self.fire(arrive: false) }
    }

    private func fire(arrive: Bool) async {
        guard enabled else { return }
        let link = d.string(forKey: arrive ? "geo.arrive" : "geo.leave") ?? ""
        let bg = UIApplication.shared.beginBackgroundTask(withName: "homeon.geo")
        defer { UIApplication.shared.endBackgroundTask(bg) }
        var said = ""
        if let u = URL(string: link), !link.isEmpty {
            for _ in 0..<3 {
                if let res = try? await URLSession.shared.data(from: u), (res.1 as? HTTPURLResponse)?.statusCode == 200 {
                    said = String(data: res.0, encoding: .utf8) ?? "בוצע"
                    break
                }
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        d.set("\(arrive ? "הגעת הביתה" : "יצאת מהבית") ב-\(f.string(from: .now))", forKey: "geo.last")
        guard !link.isEmpty else { return }
        let n = UNMutableNotificationContent()
        n.title = arrive ? "ברוך הבא הביתה" : "יצאת מהבית"
        n.body = said.isEmpty ? "לא הצלחתי להפעיל את המכשירים. בדוק חיבור לאינטרנט." : (arrive ? "HomeOn הפעילה את מה שביקשת." : "HomeOn כיבתה את מה שביקשת.")
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "geo", content: n, trigger: nil))
    }
}

/// The washing machine countdown on the lock screen.
@MainActor
enum WashLive {
    static func update(device: String, name: String, end: Date, phase: String) async {
        let now = Date()
        let existing = Activity<WashActivityAttributes>.activities.first { $0.attributes.device == device }
        let start = existing?.content.state.start ?? now
        let st = WashActivityAttributes.ContentState(start: start, end: max(end, start.addingTimeInterval(60)), phase: phase, done: false)
        let content = ActivityContent(state: st, staleDate: end.addingTimeInterval(20 * 60))
        if let a = existing {
            await a.update(content)
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            _ = try? Activity<WashActivityAttributes>.request(attributes: WashActivityAttributes(device: device, name: name), content: content)
        }
    }
    static func end(device: String, done: Bool) async {
        for a in Activity<WashActivityAttributes>.activities where a.attributes.device == device {
            var st = a.content.state
            st.done = done
            await a.end(ActivityContent(state: st, staleDate: nil), dismissalPolicy: done ? .after(.now.addingTimeInterval(45 * 60)) : .immediate)
        }
    }
}

/// Bridge actions for the new native features.
@MainActor
enum HomeNative {
    static func json(_ o: [String: Any]) -> String {
        (try? JSONSerialization.data(withJSONObject: o)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    static func handle(_ action: String, _ body: [String: Any]) async throws -> String? {
        switch action {
        case "diag":
            _ = Store.shared
            return json(["group": Store.appGroup, "profile": Store.groupInfo, "shared": Store.groupWorks,
                         "store": SharedDefaults.shared.mode, "key": !HomeLink.key.isEmpty, "keychain": SharedPrefs.shared.usesKeychain ? "\(SharedPrefs.accessGroup) \(SharedPrefs.status)" : "no", "devices": HomeLink.devices.count, "bundle": Bundle.main.bundleIdentifier ?? ""])
        case "config":   // server, key, devices, scenes, widget choice → Siri and the widget
            if let a = body["api"] as? String, !a.isEmpty { HomeLink.api = a }
            if let k = body["key"] as? String { HomeLink.key = k }
            if let ds = body["devices"] as? [[String: Any]] {
                let old = Dictionary(uniqueKeysWithValues: HomeLink.devices.map { ($0.id, $0) })
                HomeLink.devices = ds.compactMap { x in
                    guard let id = x["id"] as? String, let n = x["name"] as? String else { return nil }
                    return HomeDevice(id: id, name: n, pcode: x["pcode"] as? String ?? "switch", room: x["room"] as? String ?? "",
                                      icon: x["icon"] as? String ?? "", on: (x["on"] as? Bool) ?? old[id]?.on, online: x["online"] as? Bool ?? true)
                }
            }
            if let sc = body["scenes"] as? [[String: Any]] {
                HomeLink.scenes = sc.compactMap { x in
                    guard let id = x["id"] as? String, let n = x["name"] as? String, let acts = x["acts"] else { return nil }
                    let a = (try? JSONSerialization.data(withJSONObject: acts)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
                    return HomeScene(id: id, name: n, acts: a)
                }
            }
            if let w = body["widget"] as? [String] { HomeLink.widgetIDs = w }
            WidgetCenter.shared.reloadAllTimelines()
            DudShortcuts.updateAppShortcutParameters()
            return json(["ok": true])
        case "geo":
            let g = HomeGeo.shared
            switch body["cmd"] as? String ?? "" {
            case "here": return json(try await g.setHere())
            case "enable": return json(try await g.enable(leave: body["leave"] as? String ?? "", arrive: body["arrive"] as? String ?? "", radius: body["radius"] as? Double))
            case "links": g.links(leave: body["leave"] as? String ?? "", arrive: body["arrive"] as? String ?? ""); return json(g.state())
            case "disable": return json(g.disable())
            case "settings":
                if let u = URL(string: UIApplication.openSettingsURLString) { await UIApplication.shared.open(u) }
                return json(g.state())
            default: return json(g.state())
            }
        case "activity":
            let dev = body["id"] as? String ?? ""
            if body["cmd"] as? String == "end" {
                await WashLive.end(device: dev, done: body["done"] as? Bool ?? false)
            } else {
                let end = Date(timeIntervalSince1970: (body["end"] as? Double ?? 0) / 1000)
                await WashLive.update(device: dev, name: body["name"] as? String ?? "מכונת כביסה", end: end, phase: body["phase"] as? String ?? "")
            }
            return json(["ok": true])
        case "notify":   // a local notification at a set time (toaster done, etc.)
            let id = "homeon." + (body["id"] as? String ?? "n")
            let c = UNUserNotificationCenter.current()
            c.removePendingNotificationRequests(withIdentifiers: [id])
            if body["cmd"] as? String == "cancel" { return json(["ok": true]) }
            let ok = (try? await c.requestAuthorization(options: [.alert, .sound])) ?? false
            let at = (body["at"] as? Double ?? 0) / 1000
            let secs = at - Date().timeIntervalSince1970
            guard ok, secs > 1 else { return json(["ok": ok]) }
            let n = UNMutableNotificationContent()
            n.title = body["title"] as? String ?? "HomeOn"
            n.body = body["body"] as? String ?? ""
            n.sound = .default
            n.interruptionLevel = .timeSensitive
            try await c.add(UNNotificationRequest(identifier: id, content: n, trigger: UNTimeIntervalNotificationTrigger(timeInterval: secs, repeats: false)))
            return json(["ok": true])
        default:
            return nil
        }
    }
}
