import Foundation
import Network
import CryptoKit
import CommonCrypto

/// Talks to Smart Life (Tuya) devices directly on the home WiFi (Tuya LAN protocol 3.3 / 3.4 / 3.5).
/// The device keys come from HomeOn's server; when a device can't be reached here, the web layer falls back to the cloud.
actor TuyaLocal {
    static let shared = TuyaLocal()

    struct Dev: Codable {
        var id: String
        var key: String
        var name: String = ""
        var ip: String?
        var ver: String?
        var net: String?
        var ok: Double?
        var err: String?
    }

    private var devs: [String: Dev] = [:]
    private var scanning: Task<Void, Never>?
    private var lastScan = Date.distantPast
    private let store = "tuya_local_devs"

    init() {
        if let d = UserDefaults.standard.data(forKey: store), let v = try? JSONDecoder().decode([String: Dev].self, from: d) { devs = v }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(devs) { UserDefaults.standard.set(d, forKey: store) }
    }

    // MARK: public

    func set(_ list: [[String: Any]]) -> Int {
        var next: [String: Dev] = [:]
        for x in list {
            guard let id = x["id"] as? String, let key = x["key"] as? String, key.utf8.count == 16 else { continue }
            var d = devs[id] ?? Dev(id: id, key: key)
            if d.key != key { d.key = key; d.ver = nil }
            d.name = x["name"] as? String ?? d.name
            next[id] = d
        }
        devs = next
        save()
        if devs.values.contains(where: { $0.ip == nil }) { kickScan(force: false) }
        return devs.count
    }

    func control(_ id: String, dps: [String: Any]) async throws {
        let (d, net) = try ready(id)
        do {
            let link = TuyaLink(host: d.ip!)
            defer { link.close() }
            try await link.open(timeout: 0.9)
            var s = try await session(link, d)
            let ts = Int(Date().timeIntervalSince1970)
            let (cmd, body): (UInt32, [String: Any]) = s.ver == "3.3"
                ? (7, ["devId": id, "uid": id, "t": String(ts), "dps": dps])
                : (13, ["protocol": 5, "t": ts, "data": ["dps": dps]])
            try await link.send(TC.encode(&s, cmd: cmd, payload: try JSONSerialization.data(withJSONObject: body)))
            let end = Date().addingTimeInterval(2.5)
            while end.timeIntervalSinceNow > 0 {
                let f = try await link.frame(timeout: end.timeIntervalSinceNow)
                guard let m = TC.decode(s, f) else { continue }
                if m.cmd == cmd || m.cmd == 8 {
                    if m.cmd == cmd && m.ret != 0 { throw TuyaError.bad("המכשיר סירב (\(m.ret))") }
                    mark(id, net: net, err: nil)
                    return
                }
            }
            throw TuyaError.timeout
        } catch {
            mark(id, net: net, err: String(describing: error), lost: true)
            throw error
        }
    }

    func query(_ id: String) async throws -> [String: Any] {
        let (d, net) = try ready(id)
        let link = TuyaLink(host: d.ip!)
        defer { link.close() }
        try await link.open(timeout: 0.9)
        var s = try await session(link, d)
        let ts = String(Int(Date().timeIntervalSince1970))
        let (cmd, payload): (UInt32, Data) = s.ver == "3.3"
            ? (10, try JSONSerialization.data(withJSONObject: ["gwId": id, "devId": id, "uid": id, "t": ts]))
            : (16, Data("{}".utf8))
        try await link.send(TC.encode(&s, cmd: cmd, payload: payload))
        let end = Date().addingTimeInterval(2.5)
        while end.timeIntervalSinceNow > 0 {
            let f = try await link.frame(timeout: end.timeIntervalSinceNow)
            guard let m = TC.decode(s, f), let j = try? JSONSerialization.jsonObject(with: m.body) as? [String: Any] else { continue }
            if let dps = j["dps"] as? [String: Any] ?? (j["data"] as? [String: Any])?["dps"] as? [String: Any] {
                mark(id, net: net, err: nil)
                return dps
            }
        }
        throw TuyaError.timeout
    }

    func diag() -> [[String: Any]] {
        devs.values.sorted { $0.name < $1.name }.map { d in
            var o: [String: Any] = ["id": d.id, "name": d.name, "found": d.ip != nil]
            if let v = d.ip { o["ip"] = v }
            if let v = d.ver { o["ver"] = v }
            if let v = d.err { o["err"] = v }
            if let v = d.ok { o["ok"] = v }
            return o
        }
    }

    var isScanning: Bool { scanning != nil }

    func kickScan(force: Bool) {
        if scanning != nil { return }
        if !force && Date().timeIntervalSince(lastScan) < 60 { return }
        lastScan = Date()
        scanning = Task { await self.scan(); self.scanning = nil }
    }

    // MARK: internals

    private func ready(_ id: String) throws -> (Dev, String) {
        guard let d = devs[id] else { throw TuyaError.unknown }
        guard let net = Net.wifiSubnet() else { throw TuyaError.notHome }
        guard d.ip != nil, d.ver != nil, d.net == net.key else { kickScan(force: false); throw TuyaError.notFound }
        return (d, net.key)
    }

    private func mark(_ id: String, net: String, err: String?, lost: Bool = false) {
        guard var d = devs[id] else { return }
        d.err = err
        if err == nil { d.ok = Date().timeIntervalSince1970 }
        if lost { d.ip = nil; d.ver = nil }
        devs[id] = d
        save()
        if lost { kickScan(force: true) }
    }

    private func session(_ link: TuyaLink, _ d: Dev) async throws -> TC.Sess {
        let key = Data(d.key.utf8)
        if d.ver == "3.3" { return TC.Sess(ver: "3.3", key: key) }
        return try await TC.negotiate(link, ver: d.ver ?? "3.4", key: key)
    }

    /// Finds which device answers on which address: open port 6668 on the home subnet, then try the keys.
    private func scan() async {
        guard let net = Net.wifiSubnet() else { return }
        let hosts = await Net.openHosts(net.hosts, port: 6668)
        var left = devs.values.filter { $0.ip == nil || $0.net != net.key }.map { ($0.id, Data($0.key.utf8)) }
        let taken = Set(devs.values.compactMap { $0.net == net.key ? $0.ip : nil })
        let todo = hosts.filter { !taken.contains($0) }
        if left.isEmpty || todo.isEmpty { return }
        let found: [(String, String, String)] = await withTaskGroup(of: (String, String, String)?.self) { g in
            for h in todo {
                let cand = left
                g.addTask { await TC.identify(host: h, keys: cand) }
            }
            var out: [(String, String, String)] = []
            for await r in g { if let r { out.append(r) } }
            return out
        }
        for (id, host, ver) in found {
            guard var d = devs[id] else { continue }
            d.ip = host; d.ver = ver; d.net = net.key; d.err = nil
            devs[id] = d
            left.removeAll { $0.0 == id }
        }
        save()
    }
}

enum TuyaError: LocalizedError {
    case unknown, notHome, notFound, timeout, closed, wrongKey, bad(String)
    var errorDescription: String? {
        switch self {
        case .unknown: return "המכשיר לא מוכר לשליטה ישירה"
        case .notHome: return "לא מחובר ל-WiFi"
        case .notFound: return "המכשיר עוד לא נמצא ברשת"
        case .timeout: return "המכשיר לא ענה"
        case .closed: return "החיבור נסגר"
        case .wrongKey: return "מפתח לא מתאים"
        case .bad(let s): return s
        }
    }
}

// MARK: - one TCP connection

final class TuyaLink {
    private let conn: NWConnection
    private let queue = DispatchQueue(label: "tuya.link")
    private var buf = Data()

    init(host: String, port: UInt16 = 6668) {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.connectionTimeout = 2
        let p = NWParameters(tls: nil, tcp: tcp)
        p.requiredInterfaceType = .wifi
        conn = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: p)
    }

    func open(timeout: Double) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            var done = false
            let finish: (Result<Void, Error>) -> Void = { r in if done { return }; done = true; c.resume(with: r) }
            conn.stateUpdateHandler = { st in
                switch st {
                case .ready: finish(.success(()))
                case .failed(let e), .waiting(let e): finish(.failure(e))
                case .cancelled: finish(.failure(TuyaError.closed))
                default: break
                }
            }
            conn.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish(.failure(TuyaError.timeout)) }
        }
    }

    func send(_ d: Data) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            conn.send(content: d, completion: .contentProcessed { e in
                if let e { c.resume(throwing: e) } else { c.resume() }
            })
        }
    }

    func frame(timeout: Double) async throws -> Data {
        let end = Date().addingTimeInterval(timeout)
        while true {
            if let f = TC.cut(&buf) { return f }
            let left = end.timeIntervalSinceNow
            if left <= 0 { throw TuyaError.timeout }
            buf.append(try await recv(timeout: left))
        }
    }

    private func recv(timeout: Double) async throws -> Data {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Data, Error>) in
            var done = false
            let finish: (Result<Data, Error>) -> Void = { r in if done { return }; done = true; c.resume(with: r) }
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, complete, err in
                if let err { finish(.failure(err)); return }
                if let data, !data.isEmpty { finish(.success(data)); return }
                finish(.failure(TuyaError.closed))
                _ = complete
            }
            queue.asyncAfter(deadline: .now() + timeout) { finish(.failure(TuyaError.timeout)) }
        }
    }

    func close() { conn.cancel() }
}

// MARK: - protocol

enum TC {
    struct Sess { let ver: String; var key: Data; var seq: UInt32 = 1 }
    struct Msg { let cmd: UInt32; let ret: UInt32; let body: Data }

    static let p55 = Data([0, 0, 0x55, 0xAA]), s55 = Data([0, 0, 0xAA, 0x55])
    static let p66 = Data([0, 0, 0x66, 0x99]), s66 = Data([0, 0, 0x99, 0x66])
    /// commands sent without the "3.x" version header
    static let noHeader: Set<UInt32> = [3, 4, 5, 9, 10, 16, 18, 64]

    static func be32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.bigEndian) { Data($0) } }
    static func be16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.bigEndian) { Data($0) } }
    static func rd32(_ d: Data, _ at: Int) -> UInt32 {
        let b = [UInt8](d[d.startIndex + at ..< d.startIndex + at + 4])
        return UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3])
    }
    static func vh(_ v: String) -> Data { Data(v.utf8) + Data(count: 12) }
    static func random(_ n: Int) -> Data { Data((0..<n).map { _ in UInt8.random(in: 0...255) }) }

    static func hmac(_ key: Data, _ d: Data) -> Data { Data(HMAC<SHA256>.authenticationCode(for: d, using: SymmetricKey(data: key))) }

    static func ecb(_ data: Data, key: Data, encrypt: Bool, pad: Bool) -> Data? {
        let cap = data.count + kCCBlockSizeAES128
        var out = Data(count: cap)
        var moved = 0
        let opts = CCOptions(kCCOptionECBMode | (pad ? kCCOptionPKCS7Padding : 0))
        let st = out.withUnsafeMutableBytes { o in
            data.withUnsafeBytes { i in
                key.withUnsafeBytes { k in
                    CCCrypt(CCOperation(encrypt ? kCCEncrypt : kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), opts,
                            k.baseAddress, key.count, nil, i.baseAddress, data.count, o.baseAddress, cap, &moved)
                }
            }
        }
        guard st == kCCSuccess else { return nil }
        return out.prefix(moved)
    }

    static func gcmSeal(_ p: Data, key: Data, iv: Data, aad: Data) throws -> (Data, Data) {
        let box = try AES.GCM.seal(p, using: SymmetricKey(data: key), nonce: try AES.GCM.Nonce(data: iv), authenticating: aad)
        return (box.ciphertext, box.tag)
    }

    static func gcmOpen(_ c: Data, key: Data, iv: Data, tag: Data, aad: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(nonce: try AES.GCM.Nonce(data: iv), ciphertext: c, tag: tag)
        return try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: aad)
    }

    private static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }
    static func crc32(_ d: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in d { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }

    static func pack55(seq: UInt32, cmd: UInt32, payload: Data, hmacKey: Data?) -> Data {
        let endLen = hmacKey == nil ? 8 : 36
        var d = p55 + be32(seq) + be32(cmd) + be32(UInt32(payload.count + endLen)) + payload
        d += hmacKey.map { hmac($0, d) } ?? be32(crc32(d))
        return d + s55
    }

    static func encode(_ s: inout Sess, cmd: UInt32, payload: Data) throws -> Data {
        defer { s.seq += 1 }
        switch s.ver {
        case "3.5":
            let p = noHeader.contains(cmd) ? payload : vh("3.5") + payload
            let hdr = p66 + be16(0) + be32(s.seq) + be32(cmd) + be32(UInt32(p.count + 28))
            let iv = random(12)
            let (ct, tag) = try gcmSeal(p, key: s.key, iv: iv, aad: hdr.dropFirst(4))
            return hdr + iv + ct + tag + s66
        case "3.4":
            let p = noHeader.contains(cmd) ? payload : vh("3.4") + payload
            guard let enc = ecb(p, key: s.key, encrypt: true, pad: true) else { throw TuyaError.bad("encrypt") }
            return pack55(seq: s.seq, cmd: cmd, payload: enc, hmacKey: s.key)
        default:
            guard var enc = ecb(payload, key: s.key, encrypt: true, pad: true) else { throw TuyaError.bad("encrypt") }
            if !noHeader.contains(cmd) { enc = vh("3.3") + enc }
            return pack55(seq: s.seq, cmd: cmd, payload: enc, hmacKey: nil)
        }
    }

    /// Splits one whole frame off the front of the buffer.
    static func cut(_ b: inout Data) -> Data? {
        if b.count < 4 { return nil }
        if b.prefix(4) != p55 && b.prefix(4) != p66 {
            let r1 = b.range(of: p55)?.lowerBound, r2 = b.range(of: p66)?.lowerBound
            guard let at = [r1, r2].compactMap({ $0 }).min() else { b = Data(b.suffix(3)); return nil }
            b = Data(b[at...])
            if b.count < 4 { return nil }
        }
        let total: Int
        if b.prefix(4) == p55 {
            guard b.count >= 16 else { return nil }
            total = 16 + Int(rd32(b, 12))
        } else {
            guard b.count >= 18 else { return nil }
            total = 18 + Int(rd32(b, 14)) + 4
        }
        guard total < 1_000_000 else { b = Data(); return nil }
        guard b.count >= total else { return nil }
        let f = Data(b.prefix(total))
        b = Data(b.dropFirst(total))
        return f
    }

    static func decode(_ s: Sess, _ f: Data) -> Msg? {
        var ret: UInt32 = 0
        var body: Data
        let cmd: UInt32
        if f.prefix(4) == p66 {
            guard f.count >= 18 + 28 + 4 else { return nil }
            cmd = rd32(f, 10)
            let len = Int(rd32(f, 14))
            let hdr = f.prefix(18)
            let iv = f[f.startIndex + 18 ..< f.startIndex + 30]
            let ct = f[f.startIndex + 30 ..< f.startIndex + 18 + len - 16]
            let tag = f[f.startIndex + 18 + len - 16 ..< f.startIndex + 18 + len]
            guard let plain = try? gcmOpen(Data(ct), key: s.key, iv: Data(iv), tag: Data(tag), aad: Data(hdr.dropFirst(4))) else { return nil }
            body = plain
            if body.count >= 4 && body.first != UInt8(ascii: "{") && !body.starts(with: Data("3.".utf8)) {
                ret = rd32(body, 0); body = Data(body.dropFirst(4))
            }
        } else {
            guard f.count >= 24 else { return nil }
            cmd = rd32(f, 8)
            let len = Int(rd32(f, 12))
            let endLen = s.ver == "3.3" ? 8 : 36
            guard len >= endLen else { return nil }
            body = Data(f[f.startIndex + 16 ..< f.startIndex + 16 + len - endLen])
            // replies carry a 4-byte return code before the (16-byte block) ciphertext
            if body.count >= 4 && !body.starts(with: Data("3.".utf8)) && ((body.count - 4) % 16 == 0 || Data(body.dropFirst(4)).starts(with: Data("3.".utf8))) {
                ret = rd32(body, 0); body = Data(body.dropFirst(4))
            }
            if s.ver == "3.3" {
                if body.starts(with: Data("3.3".utf8)) { body = Data(body.dropFirst(15)) }
            }
            if !body.isEmpty {
                guard let plain = ecb(body, key: s.key, encrypt: false, pad: true) else { return nil }
                body = plain
            }
        }
        if body.starts(with: Data(s.ver.utf8)) && body.count >= 15 { body = Data(body.dropFirst(15)) }
        return Msg(cmd: cmd, ret: ret, body: body)
    }

    /// 3.4 / 3.5 session key handshake.
    static func negotiate(_ link: TuyaLink, ver: String, key: Data, timeout: Double = 1.5) async throws -> Sess {
        var s = Sess(ver: ver, key: key)
        let nonce = random(16)
        try await link.send(try encode(&s, cmd: 3, payload: nonce))
        let end = Date().addingTimeInterval(timeout)
        var remote: Data?
        while end.timeIntervalSinceNow > 0 {
            let f = try await link.frame(timeout: end.timeIntervalSinceNow)
            guard let m = decode(s, f) else { throw TuyaError.wrongKey }
            if m.cmd != 4 { continue }
            guard m.body.count >= 48, m.body.subdata(in: m.body.startIndex + 16 ..< m.body.startIndex + 48) == hmac(key, nonce) else { throw TuyaError.wrongKey }
            remote = Data(m.body.prefix(16))
            break
        }
        guard let remote else { throw TuyaError.timeout }
        try await link.send(try encode(&s, cmd: 5, payload: hmac(key, remote)))
        let x = Data(zip(nonce, remote).map { $0 ^ $1 })
        if ver == "3.4" {
            guard let k = ecb(x, key: key, encrypt: true, pad: false) else { throw TuyaError.bad("key") }
            s.key = k
        } else {
            s.key = try gcmSeal(x, key: key, iv: Data(nonce.prefix(12)), aad: Data()).0
        }
        return s
    }

    /// Which of these devices (id, key) is at this address, and which protocol version it speaks.
    /// A device drops a message made with another device's key, so each key is tried in turn.
    static func identify(host: String, keys: [(String, Data)]) async -> (String, String, String)? {
        for ver in ["3.4", "3.5"] {
            for (id, k) in keys where (try? await probeNeg(host: host, ver: ver, key: k)) == true { return (id, host, ver) }
        }
        for (id, k) in keys where (try? await probe33(host: host, id: id, key: k)) == true { return (id, host, "3.3") }
        return nil
    }

    static func probeNeg(host: String, ver: String, key: Data) async throws -> Bool {
        let link = TuyaLink(host: host)
        defer { link.close() }
        try await link.open(timeout: 0.9)
        _ = try await negotiate(link, ver: ver, key: key, timeout: 1.0)
        return true
    }

    static func probe33(host: String, id: String, key: Data) async throws -> Bool {
        let link = TuyaLink(host: host)
        defer { link.close() }
        try await link.open(timeout: 0.9)
        var s = Sess(ver: "3.3", key: key)
        let ts = String(Int(Date().timeIntervalSince1970))
        try await link.send(try encode(&s, cmd: 10, payload: try JSONSerialization.data(withJSONObject: ["gwId": id, "devId": id, "uid": id, "t": ts])))
        let f = try await link.frame(timeout: 0.9)
        guard let m = decode(s, f) else { return false }
        return m.body.first == UInt8(ascii: "{") || (m.body.isEmpty && m.ret == 0 && m.cmd == 10)
    }
}

// MARK: - home network helpers

enum Net {
    struct Subnet { let key: String; let hosts: [String] }

    /// The phone's WiFi address range (at most the /24 around it).
    static func wifiSubnet() -> Subnet? {
        var ifa: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifa) == 0, let first = ifa else { return nil }
        defer { freeifaddrs(ifa) }
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = p {
            defer { p = cur.pointee.ifa_next }
            let i = cur.pointee
            guard String(cString: i.ifa_name) == "en0", let a = i.ifa_addr, a.pointee.sa_family == UInt8(AF_INET), let m = i.ifa_netmask else { continue }
            let ip = a.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            var mask = m.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            if mask < 0xFFFFFF00 { mask = 0xFFFFFF00 }
            let netw = ip & mask
            let count = Int(~mask) - 1
            guard count > 0 else { return nil }
            let str: (UInt32) -> String = { "\($0 >> 24 & 255).\($0 >> 16 & 255).\($0 >> 8 & 255).\($0 & 255)" }
            let hosts = (1...count).map { netw + UInt32($0) }.filter { $0 != ip }.map(str)
            return Subnet(key: str(netw) + "/" + String(mask.nonzeroBitCount), hosts: hosts)
        }
        return nil
    }

    /// Addresses with the Tuya port open (64 at a time).
    static func openHosts(_ hosts: [String], port: UInt16) async -> [String] {
        var out: [String] = []
        var i = 0
        while i < hosts.count {
            let chunk = Array(hosts[i ..< min(i + 64, hosts.count)])
            i += 64
            let found = await withTaskGroup(of: String?.self) { g -> [String] in
                for h in chunk {
                    g.addTask {
                        let l = TuyaLink(host: h, port: port)
                        defer { l.close() }
                        return (try? await l.open(timeout: 0.8)) != nil ? h : nil
                    }
                }
                var r: [String] = []
                for await x in g { if let x { r.append(x) } }
                return r
            }
            out += found
        }
        return out
    }
}
