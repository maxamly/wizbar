import Darwin
import Foundation

enum Wiz {
    static let port: UInt16 = 38899

    static let pushPort: UInt16 = 38900

    @discardableResult
    static func request(_ payload: [String: Any], to hosts: [String],
                        timeout: TimeInterval = 1.5, expectOne: Bool = false,
                        onReply: ((String, [String: Any]) -> Void)? = nil) -> [String: [String: Any]] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0, let data = try? JSONSerialization.data(withJSONObject: payload) else { return [:] }
        defer { close(fd) }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: 0, tv_usec: 100_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        func sendAll() {
            for host in hosts {
                var addr = sockaddr_in()
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = port.bigEndian
                inet_pton(AF_INET, host, &addr.sin_addr)
                data.withUnsafeBytes { buf in
                    withUnsafePointer(to: &addr) {
                        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                            _ = sendto(fd, buf.baseAddress, buf.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }
                }
            }
        }

        var replies: [String: [String: Any]] = [:]
        var buf = [UInt8](repeating: 0, count: 4096)
        let deadline = Date().addingTimeInterval(timeout)
        var nextSend = Date()

        while Date() < deadline {
            if Date() >= nextSend {
                sendAll()
                nextSend = Date().addingTimeInterval(0.4)
            }
            var from = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, &buf, buf.count, 0, $0, &len) }
            }
            guard n > 0,
                  let json = try? JSONSerialization.jsonObject(with: Data(buf[0..<n])) as? [String: Any]
            else { continue }
            let ip = ipString(from.sin_addr)
            if replies[ip] == nil { onReply?(ip, json) }
            replies[ip] = json
            if expectOne { break }
        }
        return replies
    }

    struct Capabilities: Codable {
        var dimmable = true
        var kelvin: ClosedRange<Double>? = 2700...6500
    }

    // moduleName class: SHTWC = tunable white, SHRGB = RGB, SOCKET = plug.
    static func capabilities(ip: String) -> Capabilities? {
        func result(_ method: String) -> [String: Any]? {
            request(["method": method, "params": [:]], to: [ip], timeout: 1, expectOne: true)
                .first?.value["result"] as? [String: Any]
        }
        guard let module = result("getSystemConfig")?["moduleName"] as? String else { return nil }
        let kind = module.split(separator: "_").dropFirst().first.map(String.init) ?? ""

        if kind.contains("SOCKET") { return Capabilities(dimmable: false, kelvin: nil) }
        guard kind.contains("TW") || kind.contains("RGB") else { return Capabilities(kelvin: nil) }

        let reported = (result("getModelConfig")?["cctRange"] as? [Int])
            ?? result("getUserConfig").flatMap { ($0["extRange"] ?? $0["whiteRange"]) as? [Int] }
        if let r = reported, let lo = r.min(), let hi = r.max(), lo < hi {
            return Capabilities(kelvin: Double(lo)...Double(hi))
        }
        return Capabilities(kelvin: kind.contains("RGB") ? 2200...6500 : 2700...6500)
    }

    static func listen(_ handler: @escaping (String, [String: Any]) -> Void) -> Bool {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return false }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = pushPort.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 else { close(fd); return false }

        Thread.detachNewThread {
            var buf = [UInt8](repeating: 0, count: 4096)
            while true {
                var from = sockaddr_in()
                var len = socklen_t(MemoryLayout<sockaddr_in>.size)
                let n = withUnsafeMutablePointer(to: &from) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, &buf, buf.count, 0, $0, &len) }
                }
                guard n > 0, let json = try? JSONSerialization.jsonObject(with: Data(buf[0..<n])) as? [String: Any]
                else { continue }
                handler(ipString(from.sin_addr), json)
            }
        }
        return true
    }

    // Bulbs drop registrations after ~30s.
    static func register(_ ips: [String]) {
        guard let first = ips.first, let me = localAddress(toward: first) else { return }
        request(["id": 1, "method": "registration",
                 "params": ["phoneIp": me, "phoneMac": "a1b2c3d4e5f6", "register": true]],
                to: ips, timeout: 0.5)
    }

    static func localAddress(toward host: String) -> String? {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        inet_pton(AF_INET, host, &addr.sin_addr)
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard connected == 0 else { return nil }
        var local = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let ok = withUnsafeMutablePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
        }
        return ok == 0 ? ipString(local.sin_addr) : nil
    }

    static func broadcastAddresses() -> [String] {
        var result: Set<String> = ["255.255.255.255"]
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0 else { return Array(result) }
        defer { freeifaddrs(ifap) }

        var cursor = ifap
        while let ifa = cursor?.pointee {
            defer { cursor = ifa.ifa_next }
            let flags = Int32(ifa.ifa_flags)
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_BROADCAST != 0, flags & IFF_LOOPBACK == 0,
                  let brd = ifa.ifa_dstaddr
            else { continue }
            let ip = brd.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { ipString($0.pointee.sin_addr) }
            result.insert(ip)
        }
        return Array(result)
    }

    private static func ipString(_ addr: in_addr) -> String {
        var addr = addr
        var out = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &addr, &out, socklen_t(INET_ADDRSTRLEN))
        return String(cString: out)
    }
}
