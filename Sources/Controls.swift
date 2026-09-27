import SwiftUI

enum Kelvin {
    static let range = 2200.0...6500.0
    static let span = range.upperBound - range.lowerBound

    /// Approximate on-screen color of white light at a given temperature.
    static func color(_ k: Double) -> Color {
        let warm = (1.0, 0.64, 0.32), mid = (1.0, 0.87, 0.66), cool = (0.78, 0.87, 1.0)
        let t = min(max((k - range.lowerBound) / span, 0), 1)
        let (a, b, u) = t < 0.5 ? (warm, mid, t * 2) : (mid, cool, (t - 0.5) * 2)
        return Color(red: a.0 + (b.0 - a.0) * u, green: a.1 + (b.1 - a.1) * u, blue: a.2 + (b.2 - a.2) * u)
    }
}

/// Round power button that glows in the light's color when on.
struct Orb: View {
    let on: Bool
    let color: Color
    var size: CGFloat = 34
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: on ? "lightbulb.fill" : "lightbulb")
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(on ? Color.black.opacity(0.6) : Color.secondary)
                .frame(width: size, height: size)
                .background(Circle().fill(on ? color : Color.primary.opacity(0.08)))
                .shadow(color: on ? color.opacity(0.7) : .clear, radius: size * 0.2)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: on)
    }
}

/// Pill-shaped brightness control (10–100%), in the style of Control Center.
struct LevelSlider: View {
    let value: Double
    let color: Color
    var height: CGFloat = 26
    var showsLabel = true
    let onChange: (Int) -> Void
    let onCommit: (Int) -> Void

    var body: some View {
        GeometryReader { geo in
            let fraction = (value - 10) / 90
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(color).frame(width: max(height, geo.size.width * CGFloat(fraction)))
                HStack {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: height * 0.42, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.45))
                    Spacer()
                    if showsLabel {
                        Text("\(Int(value.rounded()))%")
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(fraction > 0.85 ? AnyShapeStyle(.black.opacity(0.5)) : AnyShapeStyle(.secondary))
                    }
                }
                .padding(.horizontal, height * 0.3)
            }
            .contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { onChange(level(at: $0.location.x, geo.size.width)) }
                .onEnded { onCommit(level(at: $0.location.x, geo.size.width)) })
        }
        .frame(height: height)
    }

    private func level(at x: CGFloat, _ width: CGFloat) -> Int {
        Int((10 + 90 * min(max(x / width, 0), 1)).rounded())
    }
}

/// Warm-to-cool white temperature control over a gradient track.
struct TempSlider: View {
    let kelvin: Double
    /// The range the bulbs actually support (e.g. 2700–6500 for tunable-white models).
    let range: ClosedRange<Double>
    var height: CGFloat = 26
    let onChange: (Int) -> Void
    let onCommit: (Int) -> Void

    private var span: Double { range.upperBound - range.lowerBound }

    var body: some View {
        GeometryReader { geo in
            let knob = height - 6
            let fraction = min(max((kelvin - range.lowerBound) / span, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(LinearGradient(
                    colors: [Kelvin.color(range.lowerBound), Kelvin.color((range.lowerBound + range.upperBound) / 2),
                             Kelvin.color(range.upperBound)],
                    startPoint: .leading, endPoint: .trailing))
                Circle()
                    .fill(.white)
                    .overlay(Circle().fill(Kelvin.color(kelvin)).padding(4))
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .frame(width: knob, height: knob)
                    .offset(x: 3 + (geo.size.width - knob - 6) * CGFloat(fraction))
            }
            .contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { onChange(kelvin(at: $0.location.x, geo.size.width)) }
                .onEnded { onCommit(kelvin(at: $0.location.x, geo.size.width)) })
        }
        .frame(height: height)
    }

    private func kelvin(at x: CGFloat, _ width: CGFloat) -> Int {
        let k = range.lowerBound + span * min(max(x / width, 0), 1)
        return Int((k / 50).rounded() * 50)
    }
}

/// Small borderless icon button used in headers.
struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Wrapping horizontal layout (for room chips).
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
