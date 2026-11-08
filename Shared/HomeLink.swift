import Foundation
import AppIntents
import WidgetKit

/// HomeOn's Smart Life devices, shared by the app, Siri and the widget (app group).
/// The web app hands over the server address, the session key, devices and scenes through the bridge.
struct HomeDevice: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var pcode: String
    var room: String = ""
    var icon: String = ""
    var on: Bool?
    var online: Bool = true
}

struct HomeScene: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    /// [{"device": id, "cmds": [ {code, value} ]}] kept as JSON, values can be any type
    var acts: String
}

enum HomeLink {
    static var defaults: SharedPrefs { SharedPrefs.shared }

    static var api: String {
        get { defaults.string(forKey: "ho.api") ?? "https://europe-west1-tab-fd9b6.cloudfunctions.net/kor" }
        set { defaults.set(newValue, forKey: "ho.api") }
    }
    static var key: String {
        get { defaults.string(forKey: "ho.key") ?? "" }
        set { defaults.set(newValue, forKey: "ho.key") }
    }
    static var devices: [HomeDevice] {
        get { load("ho.devices") ?? [] }
        set { save(newValue, "ho.devices") }
    }
    static var scenes: [HomeScene] {
        get { load("ho.scenes") ?? [] }
        set { save(newValue, "ho.scenes") }
    }
    /// Devices chosen for the widget, in order. Empty = the first devices.
    static var widgetIDs: [String] {
        get { defaults.stringArray(forKey: "ho.widget") ?? [] }
        set { defaults.set(newValue, forKey: "ho.widget") }
    }
    /// Recent taps, so a slow cloud status doesn't flip the widget back.
    static var pending: [String: Double] {
        get { defaults.dictionary(forKey: "ho.pending") as? [String: Double] ?? [:] }
        set { defaults.set(newValue, forKey: "ho.pending") }
    }

    static var widgetDevices: [HomeDevice] {
        let all = devices
        let ids = widgetIDs
        if ids.isEmpty { return Array(all.prefix(6)) }
        return ids.compactMap { id in all.first { $0.id == id } }
    }

    private static func load<T: Decodable>(_ k: String) -> T? {
        guard let d = defaults.data(forKey: k) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }
    private static func save<T: Encodable>(_ v: T, _ k: String) {
        defaults.set(try? JSONEncoder().encode(v), forKey: k)
    }

    enum Failure: LocalizedError {
        case notLinked, server(String)
        var errorDescription: String? {
            switch self {
            case .notLinked: return "צריך לפתוח את HomeOn פעם אחת כדי לחבר"
            case .server(let s): return s
            }
        }
    }

    static func post(_ path: String, _ body: [String: Any]) async throws -> [String: Any] {
        guard !key.isEmpty, let url = URL(string: api.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path) else { throw Failure.notLinked }
        var r = URLRequest(url: url, timeoutInterval: 20)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(key, forHTTPHeaderField: "X-Kor-Key")
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (d, _) = try await URLSession.shared.data(for: r)
        guard let j = try JSONSerialization.jsonObject(with: d) as? [String: Any] else { throw Failure.server("השרת לא ענה") }
        if j["ok"] as? Bool != true { throw Failure.server(j["error"] as? String ?? "שגיאה") }
        return j
    }

    static func send(_ id: String, _ cmds: [[String: Any]]) async throws {
        _ = try await post("/command", ["id": id, "commands": cmds])
    }

    static func setPower(_ id: String, _ on: Bool) async throws {
        guard let d = devices.first(where: { $0.id == id }) else { throw Failure.server("המכשיר לא נמצא") }
        try await send(id, [["code": d.pcode.isEmpty ? "switch" : d.pcode, "value": on]])
        mark(id, on)
    }

    static func mark(_ id: String, _ on: Bool) {
        var all = devices
        if let i = all.firstIndex(where: { $0.id == id }) { all[i].on = on; devices = all }
        var p = pending; p[id] = Date().timeIntervalSince1970; pending = p
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Fresh on/off for some devices, keeping taps from the last minute.
    @discardableResult
    static func refresh(_ ids: [String]) async -> [HomeDevice] {
        guard !ids.isEmpty, let j = try? await post("/states", ["ids": ids]), let st = j["states"] as? [String: [String: Any]] else { return devices }
        let p = pending, now = Date().timeIntervalSince1970
        var all = devices
        for i in all.indices {
            guard let s = st[all[i].id] else { continue }
            all[i].online = s["online"] as? Bool ?? true
            if let on = s["on"] as? Bool, now - (p[all[i].id] ?? 0) > 60 { all[i].on = on }
        }
        devices = all
        return all
    }

    static func run(_ scene: HomeScene) async throws -> Int {
        guard let data = scene.acts.data(using: .utf8),
              let acts = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return 0 }
        var ok = 0
        for a in acts {
            guard let d = a["device"] as? String, let c = a["cmds"] as? [[String: Any]] else { continue }
            if (try? await send(d, c)) != nil { ok += 1 }
        }
        return ok
    }
}

// MARK: - Siri and Shortcuts

struct DeviceEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "מכשיר"
    static var defaultQuery = DeviceQuery()
    var id: String
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    init(_ d: HomeDevice) { id = d.id; name = d.name }
}

struct DeviceQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [DeviceEntity] {
        HomeLink.devices.filter { identifiers.contains($0.id) }.map(DeviceEntity.init)
    }
    func suggestedEntities() async throws -> [DeviceEntity] { HomeLink.devices.map(DeviceEntity.init) }
    func entities(matching string: String) async throws -> [DeviceEntity] {
        let q = string.trimmingCharacters(in: .whitespaces)
        return HomeLink.devices.filter { $0.name.localizedCaseInsensitiveContains(q) || q.localizedCaseInsensitiveContains($0.name) }.map(DeviceEntity.init)
    }
}

struct SceneEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "סצנה"
    static var defaultQuery = SceneQuery()
    var id: String
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    init(_ s: HomeScene) { id = s.id; name = s.name }
    init(id: String, name: String) { self.id = id; self.name = name }
}

struct SceneQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [SceneEntity] {
        HomeLink.scenes.filter { identifiers.contains($0.id) }.map(SceneEntity.init)
    }
    func suggestedEntities() async throws -> [SceneEntity] { HomeLink.scenes.map(SceneEntity.init) }
    func entities(matching string: String) async throws -> [SceneEntity] {
        HomeLink.scenes.filter { $0.name.localizedCaseInsensitiveContains(string) }.map(SceneEntity.init)
    }
}

struct DeviceOnIntent: AppIntent {
    static var title: LocalizedStringResource = "הדלקת מכשיר"
    static var description = IntentDescription("מדליק מכשיר ב-HomeOn.")
    @Parameter(title: "מכשיר") var device: DeviceEntity
    init() {}
    static var parameterSummary: some ParameterSummary { Summary("הדלק את \(\.$device)") }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await HomeLink.setPower(device.id, true)
        return .result(dialog: "\(device.name) נדלק")
    }
}

struct DeviceOffIntent: AppIntent {
    static var title: LocalizedStringResource = "כיבוי מכשיר"
    static var description = IntentDescription("מכבה מכשיר ב-HomeOn.")
    @Parameter(title: "מכשיר") var device: DeviceEntity
    init() {}
    static var parameterSummary: some ParameterSummary { Summary("כבה את \(\.$device)") }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await HomeLink.setPower(device.id, false)
        return .result(dialog: "\(device.name) כבה")
    }
}

struct RunSceneIntent: AppIntent {
    static var title: LocalizedStringResource = "הפעלת סצנה"
    static var description = IntentDescription("מפעיל סצנה של HomeOn.")
    @Parameter(title: "סצנה") var scene: SceneEntity
    init() {}
    init(scene: SceneEntity) { self.scene = scene }
    static var parameterSummary: some ParameterSummary { Summary("הפעל את \(\.$scene)") }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let s = HomeLink.scenes.first(where: { $0.id == scene.id }) else { throw HomeLink.Failure.server("הסצנה לא נמצאה") }
        _ = try await HomeLink.run(s)
        return .result(dialog: "\"\(s.name)\" בוצעה")
    }
}

/// A widget button: flips one device.
struct DeviceToggleIntent: AppIntent {
    static var title: LocalizedStringResource = "הדלקה או כיבוי"
    static var isDiscoverable = false
    @Parameter(title: "מכשיר") var deviceID: String
    init() {}
    init(_ id: String) { deviceID = id }
    func perform() async throws -> some IntentResult {
        let id = deviceID
        let on = HomeLink.devices.first { $0.id == id }?.on ?? false
        HomeLink.mark(id, !on)
        do { try await HomeLink.setPower(id, !on) } catch { HomeLink.mark(id, on); throw error }
        return .result()
    }
}
