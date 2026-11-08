import Foundation
import Security

/// Settings shared by the app and its widget / Siri extension.
/// Normally an App Group. Some re-signed installs (e.g. Sideloadly with a free Apple ID) get no App Group,
/// but they do get the team's keychain ("TEAMID.*"), so then the same values live in one shared keychain item.
final class SharedDefaults {
    static let shared = SharedDefaults()
    private let group = UserDefaults(suiteName: Store.appGroup)
    let useGroup = Store.groupWorks
    private let service = "com.elior.homeon.shared"
    private lazy var accessGroup: String? = SharedDefaults.teamPrefix().map { $0 + ".com.elior.homeon.shared" }

    /// The team prefix this install's keychain uses (read back from a probe item).
    static func teamPrefix() -> String? {
        let probe: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.elior.homeon.probe",
                                    kSecAttrAccount as String: "probe", kSecReturnAttributes as String: true]
        var out: CFTypeRef?
        var st = SecItemCopyMatching(probe as CFDictionary, &out)
        if st == errSecItemNotFound {
            var add = probe; add.removeValue(forKey: kSecReturnAttributes as String)
            add[kSecValueData as String] = Data("1".utf8)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
            st = SecItemCopyMatching(probe as CFDictionary, &out)
        }
        guard st == errSecSuccess, let a = out as? [String: Any], let g = a[kSecAttrAccessGroup as String] as? String,
              let dot = g.firstIndex(of: ".") else { return nil }
        return String(g[..<dot])
    }

    private func query() -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "all"]
        if let g = accessGroup { q[kSecAttrAccessGroup as String] = g }
        return q
    }
    private func readAll() -> [String: Any] {
        var q = query(); q[kSecReturnData as String] = true
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data,
              let p = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any] else { return [:] }
        return p
    }
    private let lock = NSLock()
    private func write(_ k: String, _ v: Any?) {
        lock.lock(); defer { lock.unlock() }
        var all = readAll()
        all[k] = v
        guard let d = try? PropertyListSerialization.data(fromPropertyList: all, format: .binary, options: 0) else { return }
        let st = SecItemUpdate(query() as CFDictionary, [kSecValueData as String: d] as CFDictionary)
        if st == errSecItemNotFound {
            var add = query(); add[kSecValueData as String] = d
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }
    private func value(_ k: String) -> Any? { useGroup ? group?.object(forKey: k) : readAll()[k] }

    func string(forKey k: String) -> String? { value(k) as? String }
    func data(forKey k: String) -> Data? { value(k) as? Data }
    func stringArray(forKey k: String) -> [String]? { value(k) as? [String] }
    func dictionary(forKey k: String) -> [String: Any]? { value(k) as? [String: Any] }
    func bool(forKey k: String) -> Bool { (value(k) as? Bool) ?? false }
    func object(forKey k: String) -> Any? { value(k) }
    func set(_ v: Any?, forKey k: String) {
        if useGroup { group?.set(v, forKey: k) } else { write(k, v) }
    }
    func removeObject(forKey k: String) { set(nil, forKey: k) }
    /// for the diagnostics line
    var mode: String { useGroup ? "app group" : (accessGroup.map { "keychain " + $0 } ?? "keychain (no team)") }
}
