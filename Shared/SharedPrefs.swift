import Foundation
import Security

/// Settings the app and its widget both read. Normally an App Group's UserDefaults; when this install has
/// no usable App Group (a free-account re-signing tool removes it), one shared Keychain item instead -
/// the profile still allows "<TEAM>.*" keychain groups, so app and widget can meet there.
final class SharedPrefs {
    static let shared = SharedPrefs()
    private let ud: UserDefaults?
    private var cache: [String: Any]?
    private let lock = NSLock()
    static var team: String = {
        _ = Store.appGroup // fills Store.teamID while reading the profile
        return Store.teamID
    }()
    static var accessGroup: String { "\(team).com.elior.dud.shared" }
    /// last keychain result, for the diagnostics line
    static var status = ""

    init() {
        ud = Store.groupWorks ? UserDefaults(suiteName: Store.appGroup) : nil
    }
    var usesKeychain: Bool { ud == nil }

    // MARK: UserDefaults-like API used by HomeLink
    func string(forKey k: String) -> String? { ud?.string(forKey: k) ?? (all()[k] as? String) }
    func data(forKey k: String) -> Data? { ud?.data(forKey: k) ?? (all()[k] as? Data) }
    func stringArray(forKey k: String) -> [String]? { ud?.stringArray(forKey: k) ?? (all()[k] as? [String]) }
    func dictionary(forKey k: String) -> [String: Any]? { ud?.dictionary(forKey: k) ?? (all()[k] as? [String: Any]) }
    func set(_ v: Any?, forKey k: String) {
        if let ud { ud.set(v, forKey: k); return }
        lock.lock(); defer { lock.unlock() }
        var d = readKC()
        if let v { d[k] = v } else { d.removeValue(forKey: k) }
        cache = d
        writeKC(d)
    }

    func dictionaryRepresentationShared() -> [String: Any] { all() }
    private func all() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        if let cache { return cache }
        let d = readKC(); cache = d; return d
    }
    /// The widget runs in its own process: always read fresh there.
    func reload() { lock.lock(); cache = nil; lock.unlock() }

    // MARK: keychain
    private func base() -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: "homeon.shared",
                                kSecAttrAccount as String: "prefs"]
        if !Self.team.isEmpty { q[kSecAttrAccessGroup as String] = Self.accessGroup }
        return q
    }
    private func readKC() -> [String: Any] {
        var q = base()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let st = SecItemCopyMatching(q as CFDictionary, &out)
        Self.status = "read \(st)"
        guard st == errSecSuccess, let d = out as? Data,
              let p = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any] else { return [:] }
        return p
    }
    private func writeKC(_ d: [String: Any]) {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: d, format: .binary, options: 0) else { return }
        let q = base()
        let upd: [String: Any] = [kSecValueData as String: data]
        var st = SecItemUpdate(q as CFDictionary, upd as CFDictionary)
        if st == errSecItemNotFound {
            var add = q
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            st = SecItemAdd(add as CFDictionary, nil)
        }
        Self.status = "write \(st)"
    }
}

extension SharedPrefs {
    func object(forKey k: String) -> Any? { ud?.object(forKey: k) ?? all2()[k] }
    func bool(forKey k: String) -> Bool { (object(forKey: k) as? Bool) ?? false }
    func double(forKey k: String) -> Double { (object(forKey: k) as? Double) ?? 0 }
    func removeObject(forKey k: String) { set(nil, forKey: k) }
    fileprivate func all2() -> [String: Any] { dictionaryRepresentationShared() }
}
