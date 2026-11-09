import SwiftUI

enum Kelvin {
    static let range = 2200.0...6500.0
    static let span = range.upperBound - range.lowerBound

    static func color(_ k: Double) -> Color {
        let warm = (1.0, 0.64, 0.32), mid = (1.0, 0.87, 0.66), cool = (0.78, 0.87, 1.0)
        let t = min(max((k - range.lowerBound) / span, 0), 1)
        let (a, b, u) = t < 0.5 ? (warm, mid, t * 2) : (mid, cool, (t - 0.5) * 2)
        return Color(red: a.0 + (b.0 - a.0) * u, green: a.1 + (b.1 - a.1) * u, blue: a.2 + (b.2 - a.2) * u)
    }

    static func describe(_ k: Double) -> String {
        switch k {
        case ..<3000: "warm white"
        case ..<4500: "neutral white"
        default: "cool white"
        }
    }
}

struct Orb: View {
    let on: Bool
    let color: Color
    var size: CGFloat = 34
    var level = 1.0
    let name: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: on ? "lightbulb.fill" : "lightbulb")
                .font(.system(size: size * 0.42, weight: .medium))
                .symbolEffect(.bounce, value: on)
                .foregroundStyle(on ? Color.black.opacity(0.6) : Color.primary.opacity(0.65))
                .frame(width: size, height: size)
                .background(Circle().fill(on ? AnyShapeStyle(RadialGradient(
                    colors: [color.mix(with: .white, by: 0.55), color],
                    center: UnitPoint(x: 0.5, y: 0.35), startRadius: 0, endRadius: size * 0.55)) : AnyShapeStyle(.clear)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(enabled), in: .circle)
        .shadow(color: on ? color.opacity(0.3 + 0.45 * level) : .clear, radius: size * (0.15 + 0.2 * level))
        .animation(.easeOut(duration: 0.2), value: on)
        .disabled(!enabled)
        .help(on ? "Turn off \(name)" : "Turn on \(name)")
        .accessibilityLabel(name)
        .accessibilityValue(on ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

let cardShape = ConcentricRectangle(corners: .concentric(minimum: 18), isUniform: true)

struct LevelSlider: View {
    let value: Double
    let color: Color
    var on = true
    var height: CGFloat = 26
    let onChange: (Int) -> Void

    @GestureState private var dragging = false
    @State private var scrolled = 0.0

    private var level: Int { Int(value.rounded()) }

    var body: some View {
        GeometryReader { geo in
            let fraction = (value - 10) / 90
            let fill = max(height, geo.size.width * CGFloat(fraction))
            let onFill: AnyShapeStyle = on ? AnyShapeStyle(.black.opacity(0.5)) : AnyShapeStyle(.secondary)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(color).frame(width: fill)
                    .shadow(color: on ? color.opacity(0.45) : .clear, radius: 6)
                    .overlay(alignment: .trailing) {
                        Capsule().fill(.black.opacity(on ? 0.22 : 0.12))
                            .frame(width: 3, height: height * 0.42)
                            .padding(.trailing, height * 0.22)
                            .opacity(fill < geo.size.width - height * 1.6 && fill > height * 1.4 ? 1 : 0)
                    }
                    .animation(dragging ? nil : .snappy(duration: 0.3), value: value)
                HStack {
                    Image(systemName: level < 40 ? "sun.min.fill" : "sun.max.fill")
                        .font(.system(size: height * 0.42, weight: .semibold))
                        .foregroundStyle(onFill)
                        .contentTransition(.symbolEffect(.replace))
                    Spacer()
                    Text("\(level)%")
                        .font(.system(size: max(10, height * 0.38), weight: .semibold).monospacedDigit())
                        .foregroundStyle(fill > geo.size.width - height * 1.6 ? onFill : AnyShapeStyle(.secondary))
                        .contentTransition(.numericText(value: value))
                }
                .padding(.horizontal, height * 0.3)
            }
            .contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0)
                .updating($dragging) { _, state, _ in state = true }
                .onChanged { update(at: $0.location.x, geo.size.width) })
            .onHorizontalScroll { dx in
                scrolled += dx / geo.size.width * 90
                let steps = Int(scrolled)
                guard steps != 0 else { return }
                scrolled -= Double(steps)
                let new = min(max(level + steps, 10), 100)
                if new != level { onChange(new) }
            }
        }
        .frame(height: height)
        .scaleEffect(y: dragging ? 1.12 : 1)
        .animation(.snappy(duration: 0.2), value: dragging)
        .sensoryFeedback(.alignment, trigger: level == 10 || level == 100) { _, atEnd in atEnd }
        .accessibilityElement()
        .accessibilityLabel("Brightness")
        .accessibilityValue("\(level)%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(min(level + 10, 100))
            case .decrement: onChange(max(level - 10, 10))
            @unknown default: break
            }
        }
    }

    private func update(at x: CGFloat, _ width: CGFloat) {
        let new = Int((10 + 90 * min(max(x / width, 0), 1)).rounded())
        if new != level { onChange(new) }
    }
}

struct TempSlider: View {
    let kelvin: Double
    let range: ClosedRange<Double>
    var on = true
    var height: CGFloat = 26
    let onChange: (Int) -> Void

    @GestureState private var dragging = false
    @State private var hovering = false
    @State private var scrolled = 0.0

    private var span: Double { range.upperBound - range.lowerBound }
    private var current: Int { Int((kelvin / 50).rounded() * 50) }

    var body: some View {
        GeometryReader { geo in
            let knob = height - 6
            let fraction = min(max((kelvin - range.lowerBound) / span, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(LinearGradient(
                    colors: [Kelvin.color(range.lowerBound), Kelvin.color((range.lowerBound + range.upperBound) / 2),
                             Kelvin.color(range.upperBound)],
                    startPoint: .leading, endPoint: .trailing))
                Text("\(current) K")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.black.opacity(0.5))
                    .contentTransition(.numericText(value: kelvin))
                    .padding(.horizontal, height * 0.4)
                    .frame(maxWidth: .infinity, alignment: fraction > 0.5 ? .leading : .trailing)
                    .opacity(dragging || hovering ? 1 : 0)
                Circle()
                    .fill(Kelvin.color(kelvin))
                    .padding(5)
                    .frame(width: knob, height: knob)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .scaleEffect(dragging ? 1.15 : 1)
                    .offset(x: 3 + (geo.size.width - knob - 6) * CGFloat(fraction))
                    .animation(dragging ? nil : .snappy(duration: 0.3), value: kelvin)
            }
            .contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0)
                .updating($dragging) { _, state, _ in state = true }
                .onChanged { update(at: $0.location.x, geo.size.width) })
            .onHorizontalScroll { dx in
                scrolled += dx / geo.size.width * span
                let steps = Int(scrolled / 50)
                guard steps != 0 else { return }
                scrolled -= Double(steps * 50)
                let new = Int(min(max(Double(current + steps * 50), range.lowerBound), range.upperBound))
                if new != current { onChange(new) }
            }
        }
        .frame(height: height)
        .saturation(on || dragging || hovering ? 1 : 0.35)
        .opacity(on || dragging || hovering ? 1 : 0.6)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: on || dragging || hovering)
        .sensoryFeedback(.alignment, trigger: kelvin <= range.lowerBound || kelvin >= range.upperBound) { _, atEnd in atEnd }
        .accessibilityElement()
        .accessibilityLabel("Color temperature")
        .accessibilityValue("\(current) K, \(Kelvin.describe(kelvin))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(Int(min(Double(current + 250), range.upperBound)))
            case .decrement: onChange(Int(max(Double(current - 250), range.lowerBound)))
            @unknown default: break
            }
        }
    }

    private func update(at x: CGFloat, _ width: CGFloat) {
        let k = range.lowerBound + span * min(max(x / width, 0), 1)
        let new = Int((k / 50).rounded() * 50)
        if new != current { onChange(new) }
    }
}

// Sideways trackpad swipes adjust a slider under the pointer; vertical ones still scroll the panel.
private final class ScrollBox {
    var hovering = false
    var action: (CGFloat) -> Void = { _ in }
    var monitor: Any?
    deinit { stop() }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, hovering, abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return event }
            if event.momentumPhase.isEmpty {
                action(event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX)
            }
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

private struct HorizontalScroll: ViewModifier {
    let action: (CGFloat) -> Void
    @State private var box = ScrollBox()

    func body(content: Content) -> some View {
        box.action = action
        return content
            .onHover { box.hovering = $0 }
            .onAppear { box.start() }
            .onDisappear { box.stop(); box.hovering = false }
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    var spinning = false
    var tint: Color?
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            // Rotating inside a fixed square keeps the spin centered.
            TimelineView(.animation(paused: !spinning || reduceMotion)) { context in
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .rotationEffect(.degrees(spinning && !reduceMotion ? context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 1) * 360 : 0))
                    .symbolEffect(.pulse, isActive: spinning && reduceMotion)
            }
            .foregroundStyle(tint == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(.black.opacity(0.65)))
            .glassCircle()
        }
        .buttonStyle(.plain)
        .glassEffect(tint.map { .regular.tint($0).interactive() } ?? .regular.interactive(), in: .circle)
        .animation(.easeOut(duration: 0.2), value: tint)
        .help(help)
        .accessibilityLabel(help)
    }
}

extension View {
    func glassCircle() -> some View {
        frame(width: 28, height: 28).contentShape(Circle())
    }

    func onHorizontalScroll(_ action: @escaping (CGFloat) -> Void) -> some View {
        modifier(HorizontalScroll(action: action))
    }
}

struct Flow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        return CGSize(width: proposal.width ?? 0, height: arrange(width, subviews).last.map { $0.maxY } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (frame, view) in zip(arrange(bounds.width, subviews), subviews) {
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return frames
    }
}
