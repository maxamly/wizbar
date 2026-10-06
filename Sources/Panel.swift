import ServiceManagement
import SwiftUI

/// The menu bar popover.
struct Panel: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var updater: Updater
    @Environment(\.openWindow) private var openWindow
    @State private var toggled: Set<String> = []
    @State private var contentHeight: CGFloat = 0
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var anyOn: Bool { store.bulbs.contains(where: \.on) }

    /// Grow with the content and only scroll when the panel would run off the screen
    /// (visible height minus the header and the gap below the menu bar).
    private var maxScrollHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 800) - 110
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
            ScrollView {
                content
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .background(GeometryReader { Color.clear.preference(key: HeightKey.self, value: $0.size.height) })
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(max(contentHeight, 80), maxScrollHeight))
            .onPreferenceChange(HeightKey.self) { contentHeight = $0 }
        }
        .frame(width: 320)
        .onAppear {
            store.scan()
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Lights").font(.system(size: 17, weight: .bold))
                Text(summary).font(.system(size: 11)).foregroundStyle(.secondary).contentTransition(.numericText())
            }
            Spacer()
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    IconButton(symbol: "arrow.trianglehead.2.clockwise", help: "Refresh", spinning: store.scanning) { store.scan() }
                        .keyboardShortcut("r")
                    if !store.bulbs.isEmpty {
                        IconButton(symbol: "power", help: anyOn ? "Turn everything off" : "Turn everything on") {
                            store.apply(store.bulbs.map(\.id), ["state": !anyOn])
                        }
                    }
                    Menu {
                        Button("Set Up Lights…", action: openSetup).keyboardShortcut(",")
                        Button("Check for Updates…") { Task { await updater.check(manual: true) } }
                        Toggle("Launch at Login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                        Divider()
                        Text("WizBar \(updater.currentVersion)")
                        Button("Quit WizBar") { NSApp.terminate(nil) }.keyboardShortcut("q")
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .semibold))
                            .glassCircle()
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .glassEffect(.regular.interactive(), in: .circle)
                    .help("More")
                    .accessibilityLabel("More")
                }
            }
        }
    }

    private func setLaunchAtLogin(_ enable: Bool) {
        try? enable ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        // If the login item is switched off in System Settings, registering needs the user's approval there.
        if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private var summary: String {
        if store.bulbs.isEmpty { return store.scanning ? "Searching…" : "No lights" }
        let on = store.bulbs.filter(\.on).count
        return on == 0 ? "All off" : "\(on) of \(store.bulbs.count) on"
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: 10) {
            updateBanner
            if store.bulbs.isEmpty {
                emptyState
            } else {
                if store.config.rooms.isEmpty { setupHint }
                ForEach(store.rooms) { room in
                    RoomCard(room: room, expanded: expandedBinding(room))
                }
            }
        }
    }

    /// Rooms start collapsed, except the single "All Lights" group before any setup.
    private func expandedBinding(_ room: Room) -> Binding<Bool> {
        let byDefault = store.config.rooms.isEmpty
        return Binding(
            get: { toggled.contains(room.id) != byDefault },
            set: { if $0 != byDefault { toggled.insert(room.id) } else { toggled.remove(room.id) } })
    }

    @ViewBuilder private var updateBanner: some View {
        switch updater.state {
        case .idle:
            EmptyView()
        case .checking:
            banner("arrow.triangle.2.circlepath", .secondary, "Checking for updates…", nil) {
                ProgressView().controlSize(.small)
            }
        case .upToDate:
            banner("checkmark.circle.fill", .green, "You're up to date", "WizBar \(updater.currentVersion)") { EmptyView() }
        case .available(let version):
            banner("arrow.down.circle.fill", .blue, "WizBar \(version) is available", "You have \(updater.currentVersion)") {
                Button("Install") { Task { await updater.install() } }
                    .buttonStyle(.glassProminent)
                    .controlSize(.small)
            }
        case .installing:
            banner("arrow.down.circle.fill", .blue, "Installing update…", "WizBar will relaunch") {
                ProgressView().controlSize(.small)
            }
        case .failed(let message):
            banner("exclamationmark.triangle.fill", .orange, "Update failed", message) {
                Button("Retry") { Task { await updater.check(manual: true) } }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
        }
    }

    private func banner(_ icon: String, _ tint: Color, _ title: String, _ subtitle: String?,
                        @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold))
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(10)
        .glassEffect(.regular, in: cardShape)
        .transition(.blurReplace)
    }

    private var setupHint: some View {
        Button(action: openSetup) {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.blue.gradient))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Group lights by room").font(.system(size: 12, weight: .semibold))
                    Text("Blink each one to see which is which").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: cardShape)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "lightbulb.slash")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text(store.scanning ? "Looking for lights…" : "No lights found")
                .font(.system(size: 13, weight: .semibold))
            if !store.scanning {
                Text("Make sure this Mac is on the same Wi-Fi as your bulbs and Local Network access is allowed.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Search Again") { store.scan() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 12)
    }

    private func openSetup() {
        openWindow(id: "setup")
        NSApp.activate()
    }
}

private struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct RoomCard: View {
    @EnvironmentObject var store: Store
    let room: Room
    @Binding var expanded: Bool

    private static let presets: [(name: String, icon: String, temp: Int, dimming: Int)] = [
        ("Night", "moon.fill", 2200, 10),
        ("Relax", "sofa.fill", 2700, 50),
        ("Read", "book.fill", 4000, 100),
        ("Focus", "sun.max.fill", 6500, 100),
    ]

    private var color: Color { room.isOn ? Kelvin.color(room.temp) : Color.primary.opacity(0.18) }
    /// Presets and per-light rows; without either there's nothing to expand.
    private var hasDetails: Bool { room.dimmable || room.bulbs.count > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Orb(on: room.isOn, color: Kelvin.color(room.temp), name: room.name, enabled: room.online) {
                    store.apply(room.ids, ["state": !room.isOn])
                }
                // The whole title row expands the card, not just the chevron.
                Button {
                    withAnimation(.snappy(duration: 0.25)) { expanded.toggle() }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(room.name).font(.system(size: 13, weight: .semibold))
                            Text(status).font(.system(size: 11)).foregroundStyle(.secondary)
                                .contentTransition(.numericText())
                        }
                        Spacer()
                        if hasDetails {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(expanded ? 90 : 0))
                                .frame(width: 28, height: 28)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!hasDetails)
                .accessibilityLabel(room.name)
                .accessibilityValue(status)
                .accessibilityHint(expanded ? "Collapse" : "Expand")
            }

            Group {
                if room.dimmable {
                    LevelSlider(value: room.dimming, color: color) {
                        store.apply(room.ids, ["state": true, "dimming": $0])
                    }
                }
                if let range = room.kelvinRange {
                    TempSlider(kelvin: room.temp, range: range) {
                        store.apply(room.ids, ["state": true, "temp": $0])
                    }
                }

                if expanded, room.dimmable {
                    GlassEffectContainer(spacing: 6) {
                        HStack(spacing: 6) {
                            ForEach(Self.presets, id: \.name) { preset($0) }
                        }
                    }
                    .transition(.blurReplace)
                }

                if expanded, room.bulbs.count > 1 {
                    VStack(spacing: 8) {
                        ForEach(room.bulbs) { BulbRow(bulb: $0) }
                    }
                    .padding(.top, 2)
                    .transition(.blurReplace)
                }
            }
            .disabled(!room.online)
        }
        .padding(12)
        .glassEffect(room.isOn ? .regular.tint(Kelvin.color(room.temp).opacity(0.3)) : .regular, in: cardShape)
        .opacity(room.online ? 1 : 0.55)
        .animation(.easeOut(duration: 0.2), value: room.isOn)
    }

    private func preset(_ p: (name: String, icon: String, temp: Int, dimming: Int)) -> some View {
        let active = isActive(p)
        return Button {
            store.apply(room.ids, ["state": true, "temp": p.temp, "dimming": p.dimming])
        } label: {
            VStack(spacing: 3) {
                Image(systemName: p.icon).font(.system(size: 12))
                Text(p.name).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(active ? AnyShapeStyle(.black.opacity(0.65)) : AnyShapeStyle(.primary.opacity(0.8)))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(active ? .regular.tint(Kelvin.color(room.temp)).interactive() : .regular.interactive(),
                     in: .rect(cornerRadius: 12))
        .accessibilityLabel(p.name)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    /// A preset is active when the lit bulbs match it (after clamping to what they support).
    private func isActive(_ p: (name: String, icon: String, temp: Int, dimming: Int)) -> Bool {
        guard room.isOn, abs(room.dimming - Double(p.dimming)) < 1 else { return false }
        guard let range = room.kelvinRange else { return true }
        return abs(room.temp - min(max(Double(p.temp), range.lowerBound), range.upperBound)) < 50
    }

    private var status: String {
        let n = room.bulbs.count
        let lights = n == 1 ? "1 light" : "\(n) lights"
        if !room.online { return "Offline · \(lights)" }
        if room.onCount == 0 { return "Off · \(lights)" }
        if room.onCount == n { return "On · \(lights)" }
        return "\(room.onCount) of \(n) on"
    }
}

struct BulbRow: View {
    @EnvironmentObject var store: Store
    let bulb: Bulb

    var body: some View {
        HStack(spacing: 8) {
            Orb(on: bulb.on, color: Kelvin.color(bulb.temp), size: 24, name: store.name(bulb), enabled: bulb.online) {
                store.apply([bulb.id], ["state": !bulb.on])
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(store.name(bulb)).font(.system(size: 12)).lineLimit(1)
                if !bulb.online {
                    Text("Offline").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if bulb.dimmable {
                LevelSlider(
                    value: bulb.dimming,
                    color: bulb.on ? Kelvin.color(bulb.temp) : Color.primary.opacity(0.18),
                    height: 20, showsLabel: false
                ) { store.apply([bulb.id], ["state": true, "dimming": $0]) }
                .frame(width: 120)
                .disabled(!bulb.online)
            }
        }
        .opacity(bulb.online ? 1 : 0.5)
        .contextMenu {
            Button("Blink") { store.blink(bulb.id) }.disabled(!bulb.online)
        }
    }
}
