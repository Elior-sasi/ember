import Foundation
import Network

public enum SwitcherError: Error, Equatable, Sendable {
    case unreachable      // nothing answered at that address
    case timeout
    case rejected         // the heater answered but refused (wrong id or key)
    case badResponse
}

/// Talks to one Switcher water heater over the home network.
/// Every call opens a short TCP session: connect, login, one command, close.
public struct SwitcherClient: Sendable {
    public var host: String
    public var deviceID: String
    public var deviceKey: String
    public var timeout: TimeInterval

    public init(host: String, deviceID: String, deviceKey: String, timeout: TimeInterval = 4) {
        self.host = host
        self.deviceID = deviceID.lowercased()
        self.deviceKey = deviceKey.lowercased()
        self.timeout = timeout
    }

    public func state() async throws -> HeaterState {
        try await session { link, sid, ts in
            let r = try await link.exchange(SwitcherProtocol.getState(session: sid, timestamp: ts, deviceID: deviceID))
            guard let s = SwitcherParse.state(r) else { throw SwitcherError.rejected }
            return s
        }
    }

    /// minutes = 0 turns on without a timer (the heater's auto-shutdown still applies).
    public func turnOn(minutes: Int) async throws {
        try await command(build: { sid, ts in
            SwitcherProtocol.control(on: true, minutes: minutes, session: sid, timestamp: ts, deviceID: deviceID)
        })
    }

    public func turnOff() async throws {
        try await command(build: { sid, ts in
            SwitcherProtocol.control(on: false, minutes: 0, session: sid, timestamp: ts, deviceID: deviceID)
        })
    }

    public func setAutoShutdown(minutes: Int) async throws {
        let secs = min(max(minutes, 60), 1439) * 60
        try await command(build: { sid, ts in
            SwitcherProtocol.setAutoShutdown(seconds: secs, session: sid, timestamp: ts, deviceID: deviceID)
        })
    }

    public func schedules() async throws -> [HeaterSchedule] {
        try await session { link, sid, ts in
            let r = try await link.exchange(SwitcherProtocol.getSchedules(session: sid, timestamp: ts, deviceID: deviceID))
            return SwitcherParse.schedules(r)
        }
    }

    public func deleteSchedule(slot: Int) async throws {
        try await command(build: { sid, ts in
            SwitcherProtocol.deleteSchedule(slot: slot, session: sid, timestamp: ts, deviceID: deviceID)
        })
    }

    /// Creates a schedule in the next free slot. Times are minutes since local midnight.
    public func createSchedule(weekdays: UInt8, startMinutes: Int, endMinutes: Int) async throws {
        let start = Self.todayTimestamp(minutes: startMinutes)
        let end = Self.todayTimestamp(minutes: endMinutes)
        try await command(build: { sid, ts in
            SwitcherProtocol.createSchedule(weekdays: weekdays, start: start, end: end, session: sid, timestamp: ts, deviceID: deviceID)
        })
    }

    // MARK: plumbing

    static func todayTimestamp(minutes: Int) -> UInt32 {
        let cal = Calendar.current
        let midnight = cal.startOfDay(for: Date())
        return UInt32(midnight.addingTimeInterval(TimeInterval(minutes * 60)).timeIntervalSince1970)
    }

    private func command(build: @escaping @Sendable (String, String) -> Data) async throws {
        try await session { link, sid, ts in
            let r = try await link.exchange(build(sid, ts))
            if r.isEmpty { throw SwitcherError.badResponse }
        }
    }

    private func session<T: Sendable>(_ body: @Sendable (TCPLink, String, String) async throws -> T) async throws -> T {
        let link = TCPLink(host: host, port: SwitcherProtocol.tcpPort, timeout: timeout)
        defer { link.close() }
        try await link.open()
        let ts = SwitcherProtocol.timestamp()
        let loginResponse = try await link.exchange(SwitcherProtocol.login(timestamp: ts, deviceKey: deviceKey))
        guard let sid = SwitcherParse.session(loginResponse) else { throw SwitcherError.rejected }
        return try await body(link, sid, ts)
    }
}

// MARK: - key search

extension SwitcherClient {
    /// The heater's login key is one byte. When only the IP and device id are known,
    /// try each value until the heater answers a state request.
    public static func findKey(host: String, deviceID: String) async -> String? {
        for k in 0...255 {
            let key = String(format: "%02x", k)
            let c = SwitcherClient(host: host, deviceID: deviceID, deviceKey: key, timeout: 1.5)
            do {
                _ = try await c.state()
                return key
            } catch SwitcherError.unreachable {
                return nil     // nothing at that address, no point continuing
            } catch {
                continue
            }
        }
        return nil
    }
}

// MARK: - TCP

final class TCPLink: @unchecked Sendable {
    private let conn: NWConnection
    private let timeout: TimeInterval
    private let queue = DispatchQueue(label: "switcher.tcp")

    init(host: String, port: UInt16, timeout: TimeInterval) {
        let params = NWParameters.tcp
        params.prohibitedInterfaceTypes = [.cellular]
        conn = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: params)
        self.timeout = timeout
    }

    func open() async throws {
        let _: Void = try await withTimeout { done in
            self.conn.stateUpdateHandler = { state in
                switch state {
                case .ready: done(.success(()))
                case .failed, .cancelled: done(.failure(SwitcherError.unreachable))
                case .waiting: done(.failure(SwitcherError.unreachable))
                default: break
                }
            }
            self.conn.start(queue: self.queue)
        }
    }

    func exchange(_ packet: Data) async throws -> Data {
        try await withTimeout { done in
            self.conn.send(content: packet, completion: .contentProcessed { err in
                if err != nil { done(.failure(SwitcherError.unreachable)); return }
                self.conn.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, err in
                    if let data, !data.isEmpty { done(.success(data)) }
                    else { done(.failure(err == nil ? SwitcherError.badResponse : SwitcherError.unreachable)) }
                }
            })
        }
    }

    func close() { conn.cancel() }

    /// Runs a callback-style operation, failing with .timeout if it doesn't finish in time.
    private func withTimeout<T: Sendable>(_ start: @escaping (@escaping @Sendable (Result<T, Error>) -> Void) -> Void) async throws -> T {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<T, Error>) in
            let once = Once()
            let finish: @Sendable (Result<T, Error>) -> Void = { result in
                if once.claim() { cont.resume(with: result) }
            }
            queue.asyncAfter(deadline: .now() + timeout) { finish(.failure(SwitcherError.timeout)) }
            start(finish)
        }
    }
}

final class Once: @unchecked Sendable {
    private var used = false
    private let lock = NSLock()
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if used { return false }
        used = true
        return true
    }
}
