import Foundation

/// Local-network protocol for Switcher water heaters (V2, V4, Touch, Mini).
/// Ported from the open-source aioswitcher library (Apache-2.0), TCP port 9957.
/// All builders take the timestamp explicitly so they can be tested.
public enum SwitcherProtocol {
    public static let tcpPort: UInt16 = 9957
    public static let udpPort: UInt16 = 20002

    // MARK: packet templates (hex), from aioswitcher/api/packets.py

    static let pad72 = String(repeating: "0", count: 72)
    static func requestFormat(_ session: String, _ ts: String) -> String {
        "\(session)340001000000000000000000\(ts)00000000000000000000f0fe"
    }
    static let noTimer = "00000000"

    public static func login(timestamp ts: String, deviceKey key: String) -> Data {
        let raw = "fef052000232a100" + requestFormat("00000000", ts) + key + pad72 + "00"
        return finish(raw)
    }

    public static func getState(session: String, timestamp ts: String, deviceID id: String) -> Data {
        finish("fef0300002320103" + requestFormat(session, ts) + id + "00")
    }

    /// on = true turns the heater on; minutes > 0 adds a timer.
    public static func control(on: Bool, minutes: Int, session: String, timestamp ts: String, deviceID id: String) -> Data {
        let timer = (on && minutes > 0) ? le32(UInt32(minutes * 60)) : noTimer
        return finish("fef05d0002320102" + requestFormat(session, ts) + id + pad72 + "000106000" + (on ? "1" : "0") + "00" + timer)
    }

    /// seconds must be between 3600 and 86340 (1 to 24 hours).
    public static func setAutoShutdown(seconds: Int, session: String, timestamp ts: String, deviceID id: String) -> Data {
        finish("fef05b0002320102" + requestFormat(session, ts) + id + pad72 + "00040400" + le32(UInt32(seconds)))
    }

    public static func getSchedules(session: String, timestamp ts: String, deviceID id: String) -> Data {
        finish("fef0570002320102" + requestFormat(session, ts) + id + pad72 + "00060000")
    }

    public static func deleteSchedule(slot: Int, session: String, timestamp ts: String, deviceID id: String) -> Data {
        finish("fef0580002320102" + requestFormat(session, ts) + id + pad72 + "000801000" + String(slot))
    }

    /// weekdays: bit mask (see `WeekdayBits`), 0 = one-off. start/end: unix timestamps.
    public static func createSchedule(weekdays: UInt8, start: UInt32, end: UInt32, session: String, timestamp ts: String, deviceID id: String) -> Data {
        let data = "01" + hex2(weekdays) + "01" + le32(start) + le32(end)
        return finish("fef0630002320102" + requestFormat(session, ts) + id + pad72 + "00030c00ff" + data)
    }

    // MARK: framing

    static func finish(_ hex: String) -> Data {
        var bytes = Data(hexString: hex)!
        // set_message_length: total length including the 4 CRC bytes, little byte first
        let length = bytes.count + 4
        bytes[2] = UInt8(length & 0xff)
        bytes[3] = UInt8((length >> 8) & 0xff)
        return sign(bytes)
    }

    static func sign(_ packet: Data) -> Data {
        let c1 = crc16(packet)
        let first = Data([UInt8(c1 & 0xff), UInt8(c1 >> 8)])
        var key = first
        key.append(Data(repeating: 0x30, count: 32))
        let c2 = crc16(key)
        var out = packet
        out.append(first)
        out.append(contentsOf: [UInt8(c2 & 0xff), UInt8(c2 >> 8)])
        return out
    }

    /// CRC-CCITT, poly 0x1021, initial value 0x1021 - same as Python's binascii.crc_hqx(data, 0x1021).
    static func crc16(_ data: Data, initial: UInt16 = 0x1021) -> UInt16 {
        var crc = initial
        for byte in data {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1
            }
        }
        return crc
    }

    // MARK: helpers

    public static func timestamp(_ date: Date = Date()) -> String {
        le32(UInt32(date.timeIntervalSince1970.rounded()))
    }
    static func le32(_ v: UInt32) -> String {
        withUnsafeBytes(of: v.littleEndian) { Data($0) }.hexString
    }
    static func hex2(_ v: UInt8) -> String { String(format: "%02x", v) }
}

// MARK: - responses

public struct HeaterState: Equatable, Codable, Sendable {
    public var isOn: Bool
    public var powerWatts: Int
    public var secondsLeft: Int
    public var secondsOn: Int
    public var autoShutdownSeconds: Int
    public init(isOn: Bool, powerWatts: Int, secondsLeft: Int, secondsOn: Int, autoShutdownSeconds: Int) {
        self.isOn = isOn; self.powerWatts = powerWatts; self.secondsLeft = secondsLeft
        self.secondsOn = secondsOn; self.autoShutdownSeconds = autoShutdownSeconds
    }
}

public struct HeaterSchedule: Equatable, Codable, Sendable, Identifiable {
    public var slot: Int
    public var weekdays: UInt8      // 0 = one-off
    public var startMinutes: Int    // minutes since local midnight
    public var endMinutes: Int
    public var id: Int { slot }
    public init(slot: Int, weekdays: UInt8, startMinutes: Int, endMinutes: Int) {
        self.slot = slot; self.weekdays = weekdays; self.startMinutes = startMinutes; self.endMinutes = endMinutes
    }
}

/// Switcher weekday bits. Note Sunday is the high bit.
public enum WeekdayBits {
    /// index 0 = Sunday ... 6 = Saturday (Israeli week order)
    public static let byIndex: [UInt8] = [0x80, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40]
    public static func mask(_ indices: Set<Int>) -> UInt8 { indices.reduce(0) { $0 | byIndex[$1] } }
    public static func indices(_ mask: UInt8) -> Set<Int> {
        Set(byIndex.enumerated().filter { mask & $0.element != 0 }.map { $0.offset })
    }
}

public enum SwitcherParse {
    /// Session id from a login response (4 bytes at offset 8), as hex.
    public static func session(_ r: Data) -> String? {
        guard r.count >= 12 else { return nil }
        return r.subdata(in: r.startIndex + 8 ..< r.startIndex + 12).hexString
    }

    public static func state(_ r: Data) -> HeaterState? {
        let b = [UInt8](r)
        guard b.count >= 101 else { return nil }
        guard b[75] == 0 || b[75] == 1 else { return nil }
        return HeaterState(
            isOn: b[75] == 1,
            powerWatts: Int(u16(b, 77)),
            secondsLeft: Int(u32(b, 89)),
            secondsOn: Int(u32(b, 93)),
            autoShutdownSeconds: Int(u32(b, 97)))
    }

    public static func schedules(_ r: Data, calendar: Calendar = .current) -> [HeaterSchedule] {
        let b = [UInt8](r)
        guard b.count > 49 else { return [] }
        var out: [HeaterSchedule] = []
        var i = 45
        let end = b.count - 4
        while i + 12 <= end {
            let slot = Int(b[i])
            let days = b[i + 2]
            let start = Date(timeIntervalSince1970: TimeInterval(u32(b, i + 4)))
            let stop = Date(timeIntervalSince1970: TimeInterval(u32(b, i + 8)))
            out.append(HeaterSchedule(slot: slot, weekdays: days,
                                      startMinutes: minutesOfDay(start, calendar), endMinutes: minutesOfDay(stop, calendar)))
            i += 16
        }
        return out.sorted { $0.startMinutes < $1.startMinutes }
    }

    static func minutesOfDay(_ d: Date, _ cal: Calendar) -> Int {
        let c = cal.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    static func u16(_ b: [UInt8], _ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i + 1]) << 8 }
    static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
    }
}

// MARK: - discovery broadcast

public struct DiscoveredHeater: Equatable, Codable, Sendable {
    public var deviceID: String
    public var deviceKey: String
    public var ip: String
    public var name: String
    public var model: String
}

public enum SwitcherDiscovery {
    static let models: [String: String] = [
        "030f": "Switcher Mini", "030b": "Switcher Touch", "01a7": "Switcher V2",
        "01a1": "Switcher V2", "0317": "Switcher V4",
    ]

    /// Parses a type-1 broadcast (165 bytes). Returns nil for anything that isn't a water heater.
    public static func parse(_ d: Data) -> DiscoveredHeater? {
        let b = [UInt8](d)
        guard b.count == 165, b[0] == 0xfe, b[1] == 0xf0 else { return nil }
        let modelHex = Data(b[74..<76]).hexString
        guard let model = models[modelHex] else { return nil }
        let nameBytes = b[42..<74].prefix(while: { $0 != 0 })
        return DiscoveredHeater(
            deviceID: Data(b[18..<21]).hexString,
            deviceKey: Data([b[40]]).hexString,
            ip: "\(b[76]).\(b[77]).\(b[78]).\(b[79])",
            name: String(decoding: nameBytes, as: UTF8.self),
            model: model)
    }
}

// MARK: - hex

extension Data {
    public init?(hexString: String) {
        let chars = Array(hexString.utf8)
        guard chars.count % 2 == 0 else { return nil }
        var out = Data(capacity: chars.count / 2)
        var i = 0
        while i < chars.count {
            guard let hi = Self.nib(chars[i]), let lo = Self.nib(chars[i + 1]) else { return nil }
            out.append(hi << 4 | lo)
            i += 2
        }
        self = out
    }
    static func nib(_ c: UInt8) -> UInt8? {
        switch c {
        case 48...57: return c - 48
        case 97...102: return c - 87
        case 65...70: return c - 55
        default: return nil
        }
    }
    public var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
