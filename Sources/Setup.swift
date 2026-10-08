import SwiftUI

struct SetupView: View {
    @EnvironmentObject var store: Store
    @State private var newRoom = ""
    @State private var renaming: String?
    @State private var newName = ""
    @Namespace private var chips

    private static let suggestions = ["Living Room", "Bedroom", "Kitchen", "Office", "Hallway", "Bathroom"]

    private var bulbs: [Bulb] {
        store.bulbs.sorted { $0.ip.compare($1.ip, options: .numeric) == .orderedAscending }
    }

    var body: some View {
        Form {
            Section {
                GlassEffectContainer(spacing: 8) {
                    Flow(spacing: 8) {
                        ForEach(store.config.rooms, id: \.self) { room in
                            HStack(spacing: 6) {
                                Text(room).font(.system(size: 12, weight: .semibold))
                                Button {
                                    withAnimation(.bouncy) { store.removeRoom(room) }
                                } label: {
                                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .help("Remove room")
                                .accessibilityLabel("Remove \(room)")
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .glassEffect(.regular.tint(.accentColor.opacity(0.35)).interactive(), in: .capsule)
                            .glassEffectID(room, in: chips)
                            .contextMenu { roomMenu(room) }
                        }
                        ForEach(Self.suggestions.filter { !store.config.rooms.contains($0) }, id: \.self) { room in
                            Button {
                                withAnimation(.bouncy) { store.addRoom(room) }
                            } label: {
                                Label(room, systemImage: "plus")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.regular.interactive(), in: .capsule)
                            .glassEffectID(room, in: chips)
                        }
                    }
                }
                .padding(.vertical, 4)

                TextField("Another room", text: $newRoom, prompt: Text("Type a room name and press Return"))
                    .onSubmit {
                        withAnimation(.bouncy) { store.addRoom(newRoom) }
                        newRoom = ""
                    }
            } header: {
                Text("Rooms")
            } footer: {
                Text("Rooms appear in the menu bar panel in this order. Right-click a room to rename or move it.")
                    .foregroundStyle(.secondary)
            }

            Section {
                if bulbs.isEmpty {
                    Text(store.scanning ? "Looking for lights…" : "No lights found.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(bulbs) { SetupRow(bulb: $0) }
                }
            } header: {
                Text("Lights")
            } footer: {
                Text("Press Blink to see which light is which, then give it a name, like Desk Lamp, and pick its room.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 620, height: 640)
        .onAppear { store.scan() }
        .alert("Rename Room", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let old = renaming { withAnimation(.bouncy) { _ = store.renameRoom(old, to: newName) } }
            }
            .disabled(!canRename)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its lights stay in the room.")
        }
    }

    private var canRename: Bool {
        let name = newName.trimmingCharacters(in: .whitespaces)
        return !name.isEmpty && (name == renaming || !store.config.rooms.contains(name))
    }

    @ViewBuilder private func roomMenu(_ room: String) -> some View {
        let rooms = store.config.rooms
        Button("Rename…") { newName = room; renaming = room }
        Divider()
        Button("Move Left") { withAnimation(.bouncy) { store.moveRoom(room, by: -1) } }
            .disabled(rooms.first == room)
        Button("Move Right") { withAnimation(.bouncy) { store.moveRoom(room, by: 1) } }
            .disabled(rooms.last == room)
        Divider()
        Button("Remove", role: .destructive) { withAnimation(.bouncy) { store.removeRoom(room) } }
    }
}

struct SetupRow: View {
    @EnvironmentObject var store: Store
    let bulb: Bulb

    private var isBlinking: Bool { store.blinking.contains(bulb.id) }

    var body: some View {
        HStack(spacing: 12) {
            Orb(on: bulb.on, color: Kelvin.color(bulb.temp), size: 30, name: store.name(bulb), enabled: bulb.online) {
                store.apply([bulb.id], ["state": !bulb.on])
            }

            VStack(alignment: .leading, spacing: 3) {
                TextField("Name", text: nameBinding, prompt: Text(store.defaultName(bulb)))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.quinary, in: .rect(cornerRadius: 8))
                Text("\(bulb.ip)\(bulb.online ? "" : " · offline")")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            Picker("Room", selection: roomBinding) {
                Text("No room").tag("")
                if !store.config.rooms.isEmpty { Divider() }
                ForEach(store.config.rooms, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            .frame(width: 150, alignment: .trailing)

            Button { store.blink(bulb.id) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "lightbulb.max.fill")
                        .symbolEffect(.pulse, isActive: isBlinking)
                    Text(isBlinking ? "Blinking" : "Blink")
                }
                .frame(width: 76)
            }
            .help("Flash this light so you can find it")
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .disabled(isBlinking || !bulb.online)
        }
        .padding(.vertical, 2)
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
