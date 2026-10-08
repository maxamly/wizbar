import SwiftUI

struct Bulb: Identifiable {
    let mac: String
    var ip: String
    var on: Bool
    var dimming: Double
    var temp: Double
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

    func supported(_ params: [String: Any]) -> [String: Any]? {
        var p = params
        if !dimmable { p["dimming"] = nil }
        if let k = p["temp"] as? Int {
            p["temp"] = kelvin.map { Int(min(max(Double(k), $0.lowerBound), $0.upperBound)) }
        }
        return p.isEmpty ? nil : p
    }

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
    var online: Bool { bulbs.contains(where: \.online) }
    var onCount: Int { bulbs.filter(\.on).count }
    var dimmable: Bool { bulbs.contains(where: \.dimmable) }

    var kelvinRange: ClosedRange<Double>? {
        let ranges = bulbs.compactMap(\.kelvin)
        guard let lo = ranges.map(\.lowerBound).min(), let hi = ranges.map(\.upperBound).max() else { return nil }
        return lo...hi
    }

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
    private static let capabilitiesKey = "capabilities"
    private var capabilities: [String: Wiz.Capabilities] {
        didSet { if let data = try? JSONEncoder().encode(capabilities) { UserDefaults.standard.set(data, forKey: Self.capabilitiesKey) } }
    }
    private var fetchingCapabilities: Set<String> = []
    // Network state is ignored briefly after a local change so stale replies don't move sliders.
    private var lastLocalChange: [String: Date] = [:]
    private var lastHeard: [String: Date] = [:]
    private var heardThisScan: Set<String> = []
    private var pushing = false
    private var pushers: Set<String> = []

    init() {
        config = UserDefaults.standard.data(forKey: Self.configKey)
            .flatMap { try? JSONDecoder().decode(Config.self, from: $0) } ?? Config()
        capabilities = UserDefaults.standard.data(forKey: Self.capabilitiesKey)
            .flatMap { try? JSONDecoder().decode([String: Wiz.Capabilities].self, from: $0) } ?? [:]
        scan()
        startPush()
    }

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

    @discardableResult
    func renameRoom(_ old: String, to new: String) -> Bool {
        let new = new.trimmingCharacters(in: .whitespaces)
        guard !new.isEmpty, let i = config.rooms.firstIndex(of: old) else { return false }
        if new == old { return true }
        guard !config.rooms.contains(new) else { return false }
        config.rooms[i] = new
        config.roomOf = config.roomOf.mapValues { $0 == old ? new : $0 }
        return true
    }

    func moveRoom(_ name: String, by offset: Int) {
        guard let i = config.rooms.firstIndex(of: name), config.rooms.indices.contains(i + offset) else { return }
        config.rooms.swapAt(i, i + offset)
    }

    func scan() {
        guard !scanning else { return }
        scanning = true
        heardThisScan = []
        let targets = Wiz.broadcastAddresses() + bulbs.map(\.ip)
        DispatchQueue.global().async {
            Wiz.request(["method": "getPilot", "params": [:]], to: targets, timeout: 1.5) { ip, reply in
                guard let bulb = Bulb(ip: ip, reply: reply) else { return }
                DispatchQueue.main.async {
                    self.heardThisScan.insert(bulb.id)
                    self.received(bulb)
                }
            }
            DispatchQueue.main.async {
                for i in self.bulbs.indices where !self.heardThisScan.contains(self.bulbs[i].id) {
                    self.bulbs[i].online = false
                }
                self.scanning = false
                self.registerForPush()
            }
        }
    }

    private func received(_ incoming: Bulb) {
        var bulb = incoming
        lastHeard[bulb.id] = Date()
        if let caps = capabilities[bulb.id] { bulb.apply(caps) } else { fetchCapabilities(bulb) }
        guard let i = bulbs.firstIndex(where: { $0.id == bulb.id }) else { bulbs.append(bulb); return }
        if isBusy(bulb) {
            bulbs[i].ip = bulb.ip
            bulbs[i].online = true
        } else {
            bulbs[i] = bulb
        }
    }

    private func isBusy(_ bulb: Bulb) -> Bool {
        if blinking.contains(bulb.id) || pending[bulb.ip] != nil || inFlight.contains(bulb.ip) { return true }
        return lastLocalChange[bulb.id].map { Date().timeIntervalSince($0) < 1.5 } ?? false
    }

    private func fetchCapabilities(_ bulb: Bulb) {
        guard fetchingCapabilities.insert(bulb.id).inserted else { return }
        DispatchQueue.global().async {
            let caps = Wiz.capabilities(ip: bulb.ip)
            DispatchQueue.main.async {
                self.fetchingCapabilities.remove(bulb.id)
                guard let caps else { return }
                self.capabilities[bulb.id] = caps
                if let i = self.bulbs.firstIndex(where: { $0.id == bulb.id }) { self.bulbs[i].apply(caps) }
            }
        }
    }

    private func startPush() {
        pushing = Wiz.listen { [weak self] ip, message in
            guard message["method"] as? String == "syncPilot", let params = message["params"] as? [String: Any],
                  let bulb = Bulb(ip: ip, reply: ["result": params])
            else { return }
            DispatchQueue.main.async {
                self?.pushers.insert(bulb.id)
                self?.received(bulb)
            }
        }
        guard pushing else { return }
        Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.markSilentBulbsOffline()
            self.registerForPush()
        }
    }

    private func registerForPush() {
        guard pushing else { return }
        let ips = bulbs.map(\.ip)
        DispatchQueue.global().async { Wiz.register(ips) }
    }

    private func markSilentBulbsOffline() {
        let cutoff = Date().addingTimeInterval(-16)
        for i in bulbs.indices where bulbs[i].online && pushers.contains(bulbs[i].id)
            && (lastHeard[bulbs[i].id] ?? .distantPast) < cutoff {
            bulbs[i].online = false
        }
    }

    func apply(_ ids: [String], _ params: [String: Any]) {
        for id in ids {
            guard let i = bulbs.firstIndex(where: { $0.id == id }), let p = bulbs[i].supported(params) else { continue }
            lastLocalChange[id] = Date()
            if let v = p["state"] as? Bool { bulbs[i].on = v }
            if let v = p["dimming"] as? Int { bulbs[i].dimming = Double(v) }
            if let v = p["temp"] as? Int {
                bulbs[i].temp = Double(v)
                bulbs[i].scene = 0
                bulbs[i].rgb = nil
            }
            send(p, to: bulbs[i].ip)
        }
    }

    private var pending: [String: [String: Any]] = [:]
    private var inFlight: Set<String> = []

    private func send(_ params: [String: Any], to ip: String) {
        pending[ip, default: [:]].merge(params) { $1 }
        if !inFlight.contains(ip) { flush(ip) }
    }

    private func flush(_ ip: String) {
        guard let params = pending.removeValue(forKey: ip) else { inFlight.remove(ip); return }
        inFlight.insert(ip)
        DispatchQueue.global().async {
            let ok = Self.setPilot(ip, params)
            DispatchQueue.main.async {
                if !ok { self.scan() }
                self.flush(ip)
            }
        }
    }

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

    @discardableResult
    private static func setPilot(_ ip: String, _ params: [String: Any], timeout: TimeInterval = 1.2) -> Bool {
        guard let reply = Wiz.request(["id": 1, "method": "setPilot", "params": params], to: [ip],
                                      timeout: timeout, expectOne: true).first?.value
        else { return false }
        return reply["error"] == nil
    }
}
