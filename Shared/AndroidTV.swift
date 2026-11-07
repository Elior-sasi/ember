import Foundation
import Network
import Security
import CryptoKit

// Google TV / Android TV remote (the "Android TV Remote v2" protocol the Google TV phone app uses).
// Pairing: TLS to port 6467 with our own client certificate, a 6-character code shown on the TV.
// Remote: TLS to port 6466 with the same certificate - keys, apps, power state.

enum TVError: LocalizedError {
    case noTV, timeout, refused(String), badCode, notPaired
    var errorDescription: String? {
        switch self {
        case .noTV: return "noTV"
        case .timeout: return "timeout"
        case .refused(let m): return m
        case .badCode: return "badCode"
        case .notPaired: return "notPaired"
        }
    }
}

// MARK: - tiny protobuf

struct PB {
    var d = Data()
    mutating func varint(_ v: UInt64) {
        var v = v
        while v >= 0x80 { d.append(UInt8(v & 0x7f) | 0x80); v >>= 7 }
        d.append(UInt8(v))
    }
    mutating func int(_ f: Int, _ v: Int) { varint(UInt64(f << 3)); varint(UInt64(bitPattern: Int64(v))) }
    mutating func bytes(_ f: Int, _ b: Data) { varint(UInt64(f << 3 | 2)); varint(UInt64(b.count)); d.append(b) }
    mutating func str(_ f: Int, _ s: String) { bytes(f, Data(s.utf8)) }
    mutating func msg(_ f: Int, _ m: PB) { bytes(f, m.d) }
    static func build(_ f: (inout PB) -> Void) -> PB { var p = PB(); f(&p); return p }

    /// Framed for the wire: varint length, then the message.
    var framed: Data { var p = PB(); p.varint(UInt64(d.count)); return p.d + d }

    enum Value { case int(UInt64), bytes(Data) }
    static func parse(_ data: Data) -> [Int: [Value]] {
        var out: [Int: [Value]] = [:]
        let b = [UInt8](data)
        var i = 0
        func rv() -> UInt64? {
            var r: UInt64 = 0, s: UInt64 = 0
            while i < b.count {
                let c = b[i]; i += 1
                r |= UInt64(c & 0x7f) << s
                if c < 0x80 { return r }
                s += 7
                if s > 63 { return nil }
            }
            return nil
        }
        while i < b.count {
            guard let key = rv() else { break }
            let f = Int(key >> 3), w = key & 7
            switch w {
            case 0: guard let v = rv() else { return out }; out[f, default: []].append(.int(v))
            case 2:
                // a broken length must not crash the app (Int(l) would trap on a huge value)
                guard let l = rv(), l <= UInt64(b.count - i) else { return out }
                out[f, default: []].append(.bytes(Data(b[i..<i + Int(l)]))); i += Int(l)
            case 1: i += 8
            case 5: i += 4
            default: return out
            }
        }
        return out
    }
    static func int(_ m: [Int: [Value]], _ f: Int) -> UInt64? { if case .int(let v)? = m[f]?.first { return v }; return nil }
    static func sub(_ m: [Int: [Value]], _ f: Int) -> [Int: [Value]]? { if case .bytes(let d)? = m[f]?.first { return parse(d) }; return nil }
    static func str(_ m: [Int: [Value]], _ f: Int) -> String? { if case .bytes(let d)? = m[f]?.first { return String(data: d, encoding: .utf8) }; return nil }
}

// MARK: - our client certificate (made once, kept in the keychain)

enum TVCert {
    static let tag = "com.elior.homeon.tvkey".data(using: .utf8)!
    static let label = "HomeOn TV remote"

    static func identity() throws -> SecIdentity {
        if let id = findIdentity() { return id }
        let key = try makeKey()
        guard let pub = SecKeyCopyPublicKey(key),
              let pkcs1 = SecKeyCopyExternalRepresentation(pub, nil) as Data? else { throw TVError.refused("key") }
        let der = try selfSigned(pkcs1: pkcs1, key: key)
        guard let cert = SecCertificateCreateWithData(nil, der as CFData) else { throw TVError.refused("cert") }
        let add: [String: Any] = [kSecClass as String: kSecClassCertificate, kSecValueRef as String: cert, kSecAttrLabel as String: label]
        SecItemAdd(add as CFDictionary, nil)
        guard let id = findIdentity() else { throw TVError.refused("identity") }
        return id
    }

    static func findIdentity() -> SecIdentity? {
        let q: [String: Any] = [kSecClass as String: kSecClassIdentity, kSecAttrLabel as String: label, kSecReturnRef as String: true]
        var r: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess, let r else { return nil }
        return (r as! SecIdentity)
    }

    /// Our public key's modulus and exponent (for the pairing secret).
    static func publicNumbers() throws -> (Data, Data) {
        let id = try identity()
        var cert: SecCertificate?
        SecIdentityCopyCertificate(id, &cert)
        guard let cert, let k = SecCertificateCopyKey(cert), let d = SecKeyCopyExternalRepresentation(k, nil) as Data? else { throw TVError.refused("pub") }
        return try rsaNumbers(d)
    }

    private static func makeKey() throws -> SecKey {
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [kSecAttrIsPermanent as String: true, kSecAttrApplicationTag as String: tag, kSecAttrLabel as String: label]
        ]
        var err: Unmanaged<CFError>?
        guard let k = SecKeyCreateRandomKey(attrs as CFDictionary, &err) else { throw TVError.refused("keygen") }
        return k
    }

    // DER helpers
    static func len(_ n: Int) -> Data {
        if n < 0x80 { return Data([UInt8(n)]) }
        var bytes: [UInt8] = []; var v = n
        while v > 0 { bytes.insert(UInt8(v & 0xff), at: 0); v >>= 8 }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }
    static func tlv(_ tag: UInt8, _ body: Data) -> Data { Data([tag]) + len(body.count) + body }
    static func seq(_ parts: Data...) -> Data { tlv(0x30, parts.reduce(Data(), +)) }
    static func oid(_ bytes: [UInt8]) -> Data { tlv(0x06, Data(bytes)) }
    static let null = Data([0x05, 0x00])

    private static func selfSigned(pkcs1: Data, key: SecKey) throws -> Data {
        let sha256rsa = seq(oid([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0b]), null)
        let rsaEnc = seq(oid([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01]), null)
        let name = seq(tlv(0x31, seq(oid([0x55, 0x04, 0x03]), tlv(0x0c, Data("atvremote".utf8)))))
        let fmt = DateFormatter(); fmt.dateFormat = "yyMMddHHmmss'Z'"; fmt.timeZone = TimeZone(identifier: "UTC"); fmt.locale = Locale(identifier: "en_US_POSIX")
        let from = Date().addingTimeInterval(-86_400)
        let validity = seq(tlv(0x17, Data(fmt.string(from: from).utf8)), tlv(0x17, Data("491231235959Z".utf8)))
        let spki = seq(rsaEnc, tlv(0x03, Data([0]) + pkcs1))
        var serial = Data((0..<8).map { _ in UInt8.random(in: 0...255) }); serial[0] &= 0x7f; serial[0] |= 0x01
        let tbs = seq(tlv(0xa0, tlv(0x02, Data([2]))), tlv(0x02, serial), sha256rsa, name, validity, name, spki)
        var err: Unmanaged<CFError>?
        guard let sig = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, tbs as CFData, &err) as Data? else { throw TVError.refused("sign") }
        return seq(tbs, sha256rsa, tlv(0x03, Data([0]) + sig))
    }

    /// PKCS#1 RSAPublicKey → (modulus, exponent), leading zero bytes removed.
    static func rsaNumbers(_ der: Data) throws -> (Data, Data) {
        let b = [UInt8](der); var i = 0
        func readLen() -> Int {
            let f = Int(b[i]); i += 1
            if f < 0x80 { return f }
            var n = 0; for _ in 0..<(f & 0x7f) { n = n << 8 | Int(b[i]); i += 1 }
            return n
        }
        guard b.count > 4, b[i] == 0x30 else { throw TVError.refused("der") }
        i += 1; _ = readLen()
        var ints: [Data] = []
        for _ in 0..<2 {
            guard i < b.count, b[i] == 0x02 else { throw TVError.refused("der") }
            i += 1; let l = readLen()
            var v = Array(b[i..<i + l]); i += l
            while v.count > 1 && v[0] == 0 { v.removeFirst() }
            ints.append(Data(v))
        }
        return (ints[0], ints[1])
    }
}

// MARK: - a framed TLS link

final class TVLink {
    private let conn: NWConnection
    private var buf = Data()
    private var waiters: [(id: Int, f: (Data) -> Void)] = []
    private var waiterSeq = 0
    private var inbox: [Data] = []
    var onMessage: ((Data) -> Void)?
    var onClose: (() -> Void)?
    private(set) var serverCert: SecCertificate?
    private let q = DispatchQueue(label: "homeon.tv")

    init(host: String, port: UInt16, identity: SecIdentity) {
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        if let sid = sec_identity_create(identity) { sec_protocol_options_set_local_identity(tls.securityProtocolOptions, sid) }
        var captured: SecCertificate?
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, trust, done in
            let t = sec_trust_copy_ref(trust).takeRetainedValue()
            if let chain = SecTrustCopyCertificateChain(t) as? [SecCertificate], let first = chain.first { captured = first }
            done(true)   // the TV uses its own self-signed certificate
        }, DispatchQueue(label: "homeon.tv.verify"))
        let params = NWParameters(tls: tls, tcp: .init())
        conn = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: params)
        self.captureCert = { captured }
    }
    private var captureCert: () -> SecCertificate? = { nil }

    func open(timeout: Double = 6) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            var done = false
            let finish: (Result<Void, Error>) -> Void = { r in if !done { done = true; c.resume(with: r) } }
            conn.stateUpdateHandler = { [weak self] st in
                switch st {
                case .ready:
                    self?.serverCert = self?.captureCert()
                    self?.readLoop(); finish(.success(()))
                case .failed(let e): finish(.failure(e)); self?.onClose?()
                case .cancelled: finish(.failure(TVError.timeout)); self?.onClose?()
                case .waiting(let e): finish(.failure(e))
                default: break
                }
            }
            conn.start(queue: q)
            q.asyncAfter(deadline: .now() + timeout) { finish(.failure(TVError.timeout)) }
        }
    }

    func send(_ m: PB) { conn.send(content: m.framed, completion: .contentProcessed { _ in }) }

    /// Waits for the next message (pairing is strictly request → answer).
    func next(timeout: Double = 30) async throws -> Data {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Data, Error>) in
            q.async {
                var done = false
                if !self.inbox.isEmpty { c.resume(returning: self.inbox.removeFirst()); return }
                self.waiterSeq += 1
                let id = self.waiterSeq
                self.waiters.append((id, { d in if !done { done = true; c.resume(returning: d) } }))
                self.q.asyncAfter(deadline: .now() + timeout) {
                    // remove the timed-out waiter, or it would swallow the next message
                    self.waiters.removeAll { $0.id == id }
                    if !done { done = true; c.resume(throwing: TVError.timeout) }
                }
            }
        }
    }

    func close() { conn.cancel() }

    private func readLoop() {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, err in
            guard let self else { return }
            if let data { self.buf.append(data); self.drain() }
            if complete || err != nil { self.onClose?(); return }
            self.readLoop()
        }
    }

    private func drain() {
        while true {
            var l = 0, s = 0, i = 0, ok = false
            let b = [UInt8](buf.prefix(10))
            while i < b.count { l |= Int(b[i] & 0x7f) << s; i += 1; if b[i - 1] < 0x80 { ok = true; break }; s += 7 }
            if ok && (l < 0 || l > 1_000_000) { buf.removeAll(); return }   // garbage: drop it instead of overflowing
            guard ok, buf.count >= i + l else { return }
            let m = buf.subdata(in: buf.startIndex + i ..< buf.startIndex + i + l)
            buf.removeSubrange(buf.startIndex ..< buf.startIndex + i + l)
            if let f = onMessage { f(m) }
            else if !waiters.isEmpty { waiters.removeFirst().f(m) }
            else { inbox.append(m) }
        }
    }
}

// MARK: - pairing

final class TVPairing {
    private var link: TVLink?

    /// Step 1: connect and ask the TV to show its code.
    func start(host: String) async throws {
        let id = try TVCert.identity()
        link?.close()   // a second try: drop the earlier pairing connection
        let l = TVLink(host: host, port: 6467, identity: id)
        link = l
        try await l.open()
        func outer(_ f: (inout PB) -> Void) -> PB { PB.build { $0.int(1, 2); $0.int(2, 200); f(&$0) } }
        func check(_ d: Data) throws { if PB.int(PB.parse(d), 2) != 200 { throw TVError.refused("pairing") } }
        let enc = PB.build { $0.int(1, 3); $0.int(2, 6) }
        l.send(outer { $0.msg(10, PB.build { $0.str(1, "atvremote"); $0.str(2, "HomeOn") }) }); try check(try await l.next())
        l.send(outer { $0.msg(20, PB.build { $0.msg(1, enc); $0.int(3, 1) }) }); try check(try await l.next())
        l.send(outer { $0.msg(30, PB.build { $0.msg(1, enc); $0.int(2, 1) }) }); try check(try await l.next())
    }

    /// Step 2: the code from the TV screen.
    func finish(code raw: String) async throws {
        guard let l = link else { throw TVError.notPaired }
        let code = raw.trimmingCharacters(in: .whitespaces).uppercased()
        guard code.count == 6, let check = UInt8(code.prefix(2), radix: 16) else { throw TVError.badCode }
        guard let srv = l.serverCert, let k = SecCertificateCopyKey(srv), let d = SecKeyCopyExternalRepresentation(k, nil) as Data? else { throw TVError.refused("server key") }
        let (sn, se) = try TVCert.rsaNumbers(d)
        let (cn, ce) = try TVCert.publicNumbers()
        var tail = Data(); var s = code.dropFirst(2)
        while s.count >= 2 { tail.append(UInt8(s.prefix(2), radix: 16) ?? 0); s = s.dropFirst(2) }
        var h = SHA256(); h.update(data: cn); h.update(data: ce); h.update(data: sn); h.update(data: se); h.update(data: tail)
        let secret = Data(h.finalize())
        guard secret.first == check else { throw TVError.badCode }
        l.send(PB.build { $0.int(1, 2); $0.int(2, 200); $0.msg(40, PB.build { $0.bytes(1, secret) }) })
        let r = try await l.next()
        l.close(); link = nil
        if PB.int(PB.parse(r), 2) != 200 { throw TVError.badCode }
    }

    func cancel() { link?.close(); link = nil }
}

// MARK: - remote session

@MainActor
final class TVRemote {
    static let shared = TVRemote()
    private var link: TVLink?
    private var active = false
    private(set) var powered: Bool?
    private(set) var volume: Int?
    private(set) var volumeMax: Int?
    private(set) var muted: Bool?
    private(set) var app: String?
    private var imeCounter = 0
    private var fieldCounter = 0
    private var sleepTask: Task<Void, Never>?
    private(set) var sleepAt: Date?
    /// HomeOn's page listens to these (power, volume, app, keyboard on the TV).
    var onEvent: ((String) -> Void)?
    private let pairing = TVPairing()

    var host: String? {
        get { UserDefaults.standard.string(forKey: "tv.host") }
        set { UserDefaults.standard.set(newValue, forKey: "tv.host"); disconnect() }
    }

    func disconnect() { link?.close(); link = nil; active = false }

    func pairStart(host: String) async throws { self.host = host; try await pairing.start(host: host) }
    func pairFinish(code: String) async throws { try await pairing.finish(code: code); try await connect() }

    func connect() async throws {
        if link != nil && active { return }
        guard let host else { throw TVError.noTV }
        guard TVCert.findIdentity() != nil else { throw TVError.notPaired }
        disconnect()
        let l = TVLink(host: host, port: 6466, identity: try TVCert.identity())
        link = l
        l.onClose = { [weak self] in Task { @MainActor in if self?.link === l { self?.link = nil; self?.active = false } } }
        l.onMessage = { [weak self] d in Task { @MainActor in self?.handle(d, l) } }
        do { try await l.open() } catch { link = nil; throw TVError.notPaired }
        for _ in 0..<40 where !active { try await Task.sleep(nanoseconds: 100_000_000) }
        if !active { disconnect(); throw TVError.notPaired }
    }

    private func handle(_ d: Data, _ l: TVLink) {
        let m = PB.parse(d)
        if m[1] != nil {
            l.send(PB.build { $0.msg(1, PB.build {
                $0.int(1, 622)
                $0.msg(2, PB.build { $0.str(1, "iPhone"); $0.str(2, "Apple"); $0.int(3, 1); $0.str(4, "1"); $0.str(5, "atvremote"); $0.str(6, "1.0.0") })
            }) })
        }
        if m[2] != nil { l.send(PB.build { $0.msg(2, PB.build { $0.int(1, 622) }) }); active = true }
        if let p = PB.sub(m, 8) { l.send(PB.build { $0.msg(9, PB.build { $0.int(1, Int(PB.int(p, 1) ?? 0)) }) }) }
        if let s = PB.sub(m, 40) { powered = (PB.int(s, 1) ?? 0) != 0; emit() }
        if let k = PB.sub(m, 20), let info = PB.sub(k, 1), let pkg = PB.str(info, 12) { app = pkg; emit() }
        if let e = PB.sub(m, 21) { imeCounter = Int(PB.int(e, 1) ?? 0); fieldCounter = Int(PB.int(e, 2) ?? 0) }
        if m[22] != nil { onEvent?(#"{"keyboard":true}"#) }
        if let v = PB.sub(m, 50) {
            volumeMax = PB.int(v, 6).map(Int.init); volume = PB.int(v, 7).map(Int.init); muted = (PB.int(v, 8) ?? 0) != 0; emit()
        }
    }

    private func emit() { onEvent?(stateJSON) }

    var stateJSON: String {
        var o: [String: Any] = ["ok": true, "paired": true]
        if let powered { o["on"] = powered }
        if let volume { o["volume"] = volume }
        if let volumeMax { o["volumeMax"] = volumeMax }
        if let muted { o["muted"] = muted }
        if let app { o["app"] = app }
        if let sleepAt { o["sleepAt"] = Int(sleepAt.timeIntervalSince1970) }
        let d = (try? JSONSerialization.data(withJSONObject: o)) ?? Data()
        return String(data: d, encoding: .utf8) ?? "{}"
    }

    /// Types into the text field that's open on the TV (search, passwords).
    func text(_ t: String) async throws {
        try await connect()
        let n = max(0, t.count - 1)
        link?.send(PB.build { $0.msg(21, PB.build {
            $0.int(1, imeCounter); $0.int(2, fieldCounter)
            $0.msg(3, PB.build { $0.int(1, 1); $0.msg(2, PB.build { $0.int(1, n); $0.int(2, n); $0.str(3, t) }) })
        }) })
    }

    /// Turns the TV off after some minutes (while HomeOn is running).
    func sleep(minutes: Int) {
        sleepTask?.cancel(); sleepTask = nil; sleepAt = nil
        guard minutes > 0 else { emit(); return }
        sleepAt = Date().addingTimeInterval(Double(minutes) * 60)
        sleepTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(minutes) * 60_000_000_000)
            guard !Task.isCancelled else { return }
            try? await self.connect()
            if self.powered != false { try? await self.key(26) }
            self.sleepAt = nil; self.emit()
        }
        emit()
    }

    func key(_ code: Int) async throws {
        try await connect()
        link?.send(PB.build { $0.msg(10, PB.build { $0.int(1, code); $0.int(2, 3) }) })
    }

    func app(_ url: String) async throws {
        try await connect()
        link?.send(PB.build { $0.msg(90, PB.build { $0.str(1, url) }) })
    }

    func state() async -> String {
        do { try await connect() } catch { return #"{"ok":false,"paired":\#(TVCert.findIdentity() != nil && host != nil)}"# }
        try? await Task.sleep(nanoseconds: 300_000_000)
        return stateJSON
    }

    /// Finds Google TVs on the home WiFi.
    func discover(seconds: Double = 4) async -> [[String: String]] {
        await withCheckedContinuation { (c: CheckedContinuation<[[String: String]], Never>) in
            let browser = NWBrowser(for: .bonjour(type: "_androidtvremote2._tcp", domain: nil), using: .tcp)
            var found: [String: NWEndpoint] = [:]
            browser.browseResultsChangedHandler = { results, _ in
                for r in results { if case .service(let name, _, _, _) = r.endpoint { found[name] = r.endpoint } }
            }
            browser.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                browser.cancel()
                Task { @MainActor in
                    var out: [[String: String]] = []
                    for (name, ep) in found {
                        if let ip = await Self.resolve(ep) { out.append(["name": name, "host": ip]) }
                    }
                    c.resume(returning: out)
                }
            }
        }
    }

    private static func resolve(_ ep: NWEndpoint) async -> String? {
        await withCheckedContinuation { (c: CheckedContinuation<String?, Never>) in
            let conn = NWConnection(to: ep, using: .tcp)
            var done = false
            conn.stateUpdateHandler = { st in
                if case .ready = st, !done {
                    done = true
                    var ip: String?
                    if case .hostPort(let h, _)? = conn.currentPath?.remoteEndpoint {
                        switch h {
                        case .ipv4(let a): ip = "\(a)"
                        case .ipv6(let a): ip = "\(a)"
                        case .name(let n, _): ip = n
                        @unknown default: break
                        }
                    }
                    conn.cancel(); c.resume(returning: ip?.components(separatedBy: "%").first)
                } else if case .failed = st, !done { done = true; conn.cancel(); c.resume(returning: nil) }
            }
            conn.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if !done { done = true; conn.cancel(); c.resume(returning: nil) } }
        }
    }
}
