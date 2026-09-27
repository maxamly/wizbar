import SwiftUI

/// Window for naming lights and assigning them to rooms.
struct SetupView: View {
    @EnvironmentObject var store: Store
    @State private var newRoom = ""

    private static let suggestions = ["Living Room", "Bedroom", "Kitchen", "Office", "Hallway", "Bathroom"]

    private var bulbs: [Bulb] {
        store.bulbs.sorted { $0.ip.compare($1.ip, options: .numeric) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Set Up Your Lights").font(.system(size: 24, weight: .bold))
                    Text("Press **Blink** to see which light it is, then give it a name and a room.")
                        .foregroundStyle(.secondary)
                }

                section("Rooms") {
                    Flow(spacing: 8) {
                        ForEach(store.config.rooms, id: \.self) { room in
                            HStack(spacing: 6) {
                                Text(room).font(.system(size: 12, weight: .medium))
                                Button { store.removeRoom(room) } label: {
                                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Remove room")
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        }
                        ForEach(Self.suggestions.filter { !store.config.rooms.contains($0) }, id: \.self) { room in
                            Button { store.addRoom(room) } label: {
                                Label(room, systemImage: "plus")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        TextField("Other room…", text: $newRoom)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                            .onSubmit { store.addRoom(newRoom); newRoom = "" }
                    }
                }

                section("Lights") {
                    if bulbs.isEmpty {
                        Text(store.scanning ? "Looking for lights…" : "No lights found.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(24)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(bulbs.enumerated()), id: \.element.id) { index, bulb in
                                if index > 0 { Divider().padding(.leading, 56) }
                                SetupRow(bulb: bulb)
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 40)
            .padding(.bottom, 32)
        }
        .frame(width: 600, height: 640)
        .onAppear { store.scan() }
    }

    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            content()
        }
    }
}

struct SetupRow: View {
    @EnvironmentObject var store: Store
    let bulb: Bulb

    private var isBlinking: Bool { store.blinking.contains(bulb.id) }

    var body: some View {
        HStack(spacing: 12) {
            Orb(on: bulb.on, color: Kelvin.color(bulb.temp), size: 30) {
                store.apply([bulb.id], ["state": !bulb.on])
            }

            VStack(alignment: .leading, spacing: 4) {
                TextField("Name, e.g. Desk Lamp", text: nameBinding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)))
                Text("\(store.defaultName(bulb)) · \(bulb.ip)\(bulb.online ? "" : " · offline")")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 8)
            }

            Picker("Room", selection: roomBinding) {
                Text("No room").tag("")
                if !store.config.rooms.isEmpty { Divider() }
                ForEach(store.config.rooms, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(width: 150)

            Button { store.blink(bulb.id) } label: {
                Label(isBlinking ? "Blinking" : "Blink", systemImage: "lightbulb.max.fill")
                    .symbolEffect(.pulse, isActive: isBlinking)
                    .frame(width: 78)
            }
            .disabled(isBlinking || !bulb.online)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { store.config.names[bulb.id] ?? "" },
            set: { store.config.names[bulb.id] = $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 })
    }

    private var roomBinding: Binding<String> {
        Binding(
            get: { store.config.roomOf[bulb.id].flatMap { store.config.rooms.contains($0) ? $0 : nil } ?? "" },
            set: { store.config.roomOf[bulb.id] = $0.isEmpty ? nil : $0 })
    }
}
