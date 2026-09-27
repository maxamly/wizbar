import SwiftUI

struct Bulb: Identifiable {
    let mac: String
    var ip: String
    var on: Bool
    var dimming: Double
    var temp: Double
    /// Active scene (0 = none) and RGB color, so blink can put the bulb back exactly as it was.
    var scene: Int
    var rgb: [Int]?
    var dimmable = true
    var kelvin: ClosedRange<Double>? = 2700...6500
    var online = true

    var id: String { mac }

    init?(ip: String, reply: [String: Any]) {
        guard let r = reply["result"] as? [String: Any], let mac = r["mac"] as? String else { return nil }
        self.mac = mac
        self.ip = ip
        on = r["state"] as? Bool ?? false
        dimming = Double(r["dimming"] as? Int ?? 100)
        temp = Double(r["temp"] as? Int ?? 4000)
        scene = r["sceneId"] as? Int ?? 0
        let color = ["r", "g", "b"].compactMap { r[$0] as? Int }
        rgb = color.count == 3 ? color : nil
    }

    mutating func apply(_ caps: Wiz.Capabilities) {
        dimmable = caps.dimmable
        kelvin = caps.kelvin
    }

    /// Drops or clamps params this device doesn't support; nil if nothing is left to send.
    func supported(_ params: [String: Any]) -> [String: Any]? {
        var p = params
        if !dimmable { p["dimming"] = nil }
        if let k = p["temp"] as? Int {
            p["temp"] = kelvin.map { Int(min(max(Double(k), $0.lowerBound), $0.upperBound)) }
        }
        return p.isEmpty ? nil : p
    }

    /// setPilot params that recreate the current state.
    var restoreParams: [String: Any] {
        guard on else { return ["state": false] }
        var p: [String: Any] = ["state": true]
        if dimmable { p["dimming"] = Int(dimming) }
        if scene != 0 {
            p["sceneId"] = scene
        } else if let rgb {
            p["r"] = rgb[0]; p["g"] = rgb[1]; p["b"] = rgb[2]
        } else if kelvin != nil {
            p["temp"] = Int(temp)
        }
        return p
    }
}

/// User-defined names and rooms, persisted in UserDefaults. Keyed by bulb MAC.
struct Config: Codable {
    var names: [String: String] = [:]
    var rooms: [String] = []
    var roomOf: [String: String] = [:]
}

struct Room: Identifiable {
    let name: String
    let bulbs: [Bulb]

    var id: String { name }
    var ids: [String] { bulbs.map(\.id) }
    var isOn: Bool { bulbs.contains(where: \.on) }
    var onCount: Int { bulbs.filter(\.on).count }
    var dimmable: Bool { bulbs.contains(where: \.dimmable) }

    /// Widest white range across the room; each bulb clamps to its own range when sent.
    var kelvinRange: ClosedRange<Double>? {
        let ranges = bulbs.compactMap(\.kelvin)
        guard let lo = ranges.map(\.lowerBound).min(), let hi = ranges.map(\.upperBound).max() else { return nil }
        return lo...hi
    }

    /// Averages over the lit bulbs, so an off bulb doesn't drag the numbers down.
    private var relevant: [Bulb] { isOn ? bulbs.filter(\.on) : bulbs }
    var dimming: Double { average(relevant.filter(\.dimmable).map(\.dimming), or: 100) }
    var temp: Double { average(relevant.filter { $0.kelvin != nil }.map(\.temp), or: 4000) }

    private func average(_ values: [Double], or fallback: Double) -> Double {
        values.isEmpty ? fallback : values.reduce(0, +) / Double(values.count)
    }
}

final class Store: ObservableObject {
    @Published private(set) var bulbs: [Bulb] = []
    @Published private(set) var scanning = false
    @Published private(set) var blinking: Set<String> = []
    @Published var config: Config {
        didSet { if let data = try? JSONEncoder().encode(config) { UserDefaults.standard.set(data, forKey: Self.configKey) } }
    }

    private static let configKey = "config"
    /// Device capabilities by MAC; fetched once per session.
    private var capabilities: [String: Wiz.Capabilities] = [:]

    init() {
        config = UserDefaults.standard.data(forKey: Self.configKey)
            .flatMap { try? JSONDecoder().decode(Config.self, from: $0) } ?? Config()
        scan()
    }

    // MARK: Naming & rooms

    func defaultName(_ bulb: Bulb) -> String { "Light " + bulb.mac.suffix(4).uppercased() }
    func name(_ bulb: Bulb) -> String { config.names[bulb.id] ?? defaultName(bulb) }

    var rooms: [Room] {
        let sorted = bulbs.sorted { name($0).localizedStandardCompare(name($1)) == .orderedAscending }
        var result = config.rooms
            .map { room in Room(name: room, bulbs: sorted.filter { config.roomOf[$0.id] == room }) }
            .filter { !$0.bulbs.isEmpty }
        let unassigned = sorted.filter { !config.rooms.contains(config.roomOf[$0.id] ?? "") }
        if !unassigned.isEmpty {
            result.append(Room(name: config.rooms.isEmpty ? "All Lights" : "Other", bulbs: unassigned))
        }
        return result
    }

    func addRoom(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !config.rooms.contains(name) else { return }
        config.rooms.append(name)
    }

    func removeRoom(_ name: String) {
        config.rooms.removeAll { $0 == name }
        config.roomOf = config.roomOf.filter { $0.value != name }
    }

    // MARK: Network

    /// Refreshes state from the network. Bulbs that don't answer are kept but marked offline.
    func scan() {
        guard !scanning else { return }
        scanning = true
        let known = capabilities
        DispatchQueue.global().async {
            let found = Wiz.request(["method": "getPilot", "params": [:]], to: Wiz.broadcastAddresses(), timeout: 2)
                .compactMap { Bulb(ip: $0.key, reply: $0.value) }

            let unknown = found.filter { known[$0.id] == nil }
            var fetched = [Wiz.Capabilities?](repeating: nil, count: unknown.count)
            fetched.withUnsafeMutableBufferPointer { out in
                DispatchQueue.concurrentPerform(iterations: out.count) { out[$0] = Wiz.capabilities(ip: unknown[$0].ip) }
            }

            DispatchQueue.main.async {
                for (bulb, caps) in zip(unknown, fetched) { self.capabilities[bulb.id] = caps }
                var merged = self.bulbs.map { var b = $0; b.online = false; return b }
                for var bulb in found {
                    if let caps = self.capabilities[bulb.id] { bulb.apply(caps) }
                    if let i = merged.firstIndex(where: { $0.id == bulb.id }) { merged[i] = bulb } else { merged.append(bulb) }
                }
                self.bulbs = merged
                self.scanning = false
            }
        }
    }

    /// Applies `setPilot` params to the local model and, unless `send` is false (mid-drag), to the bulbs.
    /// Params each bulb can't handle are dropped or clamped to its range.
    func apply(_ ids: [String], _ params: [String: Any], send: Bool = true) {
        for id in ids {
            guard let i = bulbs.firstIndex(where: { $0.id == id }), let p = bulbs[i].supported(params) else { continue }
            if let v = p["state"] as? Bool { bulbs[i].on = v }
            if let v = p["dimming"] as? Int { bulbs[i].dimming = Double(v) }
            if let v = p["temp"] as? Int {
                bulbs[i].temp = Double(v)
                bulbs[i].scene = 0
                bulbs[i].rgb = nil
            }
            guard send else { continue }
            let ip = bulbs[i].ip
            DispatchQueue.global().async {
                // No reply or an error means our local state may be wrong: resync.
                if !Self.setPilot(ip, p) { DispatchQueue.main.async { self.scan() } }
            }
        }
    }

    /// Flashes a bulb a few times so it can be located, then restores its previous state.
    func blink(_ id: String) {
        guard let bulb = bulbs.first(where: { $0.id == id }), !blinking.contains(id) else { return }
        blinking.insert(id)
        let lit: [String: Any] = bulb.dimmable ? ["state": true, "dimming": 100] : ["state": true]
        DispatchQueue.global().async {
            for step in 0..<6 {
                let isLit = (step + (bulb.on ? 1 : 0)).isMultiple(of: 2)
                Self.setPilot(bulb.ip, isLit ? lit : ["state": false], timeout: 0.35)
                usleep(300_000)
            }
            Self.setPilot(bulb.ip, bulb.restoreParams)
            DispatchQueue.main.async { self.blinking.remove(id) }
        }
    }

    /// Returns true if the device acknowledged without an error.
    @discardableResult
    private static func setPilot(_ ip: String, _ params: [String: Any], timeout: TimeInterval = 1.2) -> Bool {
        guard let reply = Wiz.request(["id": 1, "method": "setPilot", "params": params], to: [ip],
                                      timeout: timeout, expectOne: true).first?.value
        else { return false }
        return reply["error"] == nil
    }
}
