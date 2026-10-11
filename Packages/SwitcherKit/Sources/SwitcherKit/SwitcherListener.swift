import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Listens for the broadcast every Switcher sends roughly every 4 seconds.
/// On iPhone this may be blocked for sideloaded apps (it needs Apple's multicast
/// entitlement); then it simply finds nothing and the user enters details by hand.
public enum SwitcherListener {
    public static func discover(seconds: Double = 8) async -> [DiscoveredHeater] {
        await Task.detached(priority: .userInitiated) { listen(seconds: seconds) }.value
    }

    static func listen(seconds: Double) -> [DiscoveredHeater] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return [] }
        defer { close(fd) }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = SwitcherProtocol.udpPort.bigEndian
        addr.sin_addr = in_addr(s_addr: 0)   // any address
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return [] }

        var found: [String: DiscoveredHeater] = [:]
        var buffer = [UInt8](repeating: 0, count: 512)
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            let n = recv(fd, &buffer, buffer.count, 0)
            if n > 0, let h = SwitcherDiscovery.parse(Data(buffer[0..<n])) {
                found[h.deviceID] = h
                break   // one heater is the common case
            }
        }
        return Array(found.values)
    }
}
