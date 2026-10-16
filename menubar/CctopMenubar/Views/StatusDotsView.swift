import QuartzCore
import SwiftUI

/// A row of per-agent marks and session dots in SwiftUI, for the notch pill and the floating
/// indicator. Dots waiting on the user breathe (see `DotBreathing`) unless macOS asks apps to
/// reduce motion.
struct StatusDotsView: View {
    enum Palette {
        /// On the notch's black pill: the theme's dark colors and white ink.
        case notch
        /// On glass that turns light or dark with what is behind it: colors and ink follow.
        case adaptive
    }

    let layout: StatusDotLayout
    let metrics: StatusDotMetrics
    let palette: Palette
    var height: CGFloat = 11
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private struct Entry {
        let item: StatusDotLayout.Item
        /// Set for a dot that breathes.
        let phase: Double?
    }

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(Self.entries(for: layout).enumerated()), id: \.offset) { _, entry in
                switch entry.item {
                case .dot(let dot, let xPos):
                    dotView(dot, phase: reduceMotion ? nil : entry.phase)
                        .frame(width: metrics.dotDiameter, height: metrics.dotDiameter)
                        .offset(x: xPos)
                case .mark(let badge, let xPos, let width):
                    Image(nsImage: AgentMark.image(for: badge, height: metrics.markHeight, ink: markInk))
                        .frame(width: width, height: metrics.markHeight)
                        .offset(x: xPos)
                case .overflow(let text, let xPos, let width):
                    Text(verbatim: text)
                        .font(Font(metrics.overflowFont as CTFont))
                        .foregroundStyle(overflowColor)
                        .fixedSize()
                        .frame(width: width, alignment: .leading)
                        .offset(x: xPos)
                }
            }
        }
        .frame(width: layout.width, height: height, alignment: .leading)
    }

    /// Each layout item, with the breathing phase of a dot that breathes.
    private static func entries(for layout: StatusDotLayout) -> [Entry] {
        var spots = layout.dotSpots.makeIterator()
        return layout.items.map { item in
            guard case .dot = item, let spot = spots.next() else { return Entry(item: item, phase: nil) }
            return Entry(item: item, phase: spot.dot.breathes ? spot.phase : nil)
        }
    }

    private var isDark: Bool { palette == .notch || colorScheme == .dark }

    private var markInk: NSColor {
        isDark ? NSColor.white.withAlphaComponent(0.6) : NSColor.black.withAlphaComponent(0.55)
    }

    private var overflowColor: Color {
        isDark ? Color.white.opacity(0.7) : Color.black.opacity(0.6)
    }

    /// The dot's color, fixed for this row's light or dark look, so the ring and the breathing
    /// fill always agree.
    private func color(for dot: StatusDotGroup.Dot) -> NSColor {
        switch palette {
        case .notch:
            return dot == .unreadDone ? .controlAccentColor : StatusColors.notchNSColor(for: dot.segmentKind)
        case .adaptive:
            let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua) ?? NSAppearance.currentDrawing()
            var resolved = MenubarIconRenderer.color(for: dot, appearance: appearance)
            appearance.performAsCurrentDrawingAppearance {
                resolved = resolved.usingColorSpace(.sRGB) ?? resolved
            }
            return resolved
        }
    }

    /// `phase` is set for a breathing dot: its ring, with a fill fading in and out over it.
    @ViewBuilder
    private func dotView(_ dot: StatusDotGroup.Dot, phase: Double?) -> some View {
        let color = color(for: dot)
        let ring = max(1.1, metrics.dotDiameter * 0.16)
        if let phase {
            ZStack {
                Circle().strokeBorder(Color(nsColor: color), lineWidth: ring)
                BreathingFill(color: color, phase: phase)
            }
        } else if dot == .unreadDone {
            Circle().strokeBorder(Color(nsColor: color), lineWidth: ring)
        } else {
            Circle().fill(Color(nsColor: color))
        }
    }
}

/// A breathing dot's fill: a round layer whose opacity Core Animation fades along
/// `DotBreathing`, so the row is not redrawn per frame.
private struct BreathingFill: NSViewRepresentable {
    let color: NSColor
    let phase: Double

    func makeNSView(context: Context) -> FillView { FillView() }

    func updateNSView(_ view: FillView, context: Context) {
        view.color = color
        view.phase = phase
    }

    final class FillView: NSView {
        var color: NSColor = .clear { didSet { needsDisplay = true } }
        var phase: Double = 0 { didSet { if phase != oldValue { startBreathing() } } }

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
        }

        required init?(coder: NSCoder) { nil }

        override var wantsUpdateLayer: Bool { true }

        override func updateLayer() {
            layer?.backgroundColor = color.cgColor
        }

        override func layout() {
            super.layout()
            layer?.cornerRadius = bounds.width / 2
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            startBreathing()
        }

        private func startBreathing() {
            guard window != nil else { return }
            layer?.add(DotBreathing.animation(phase: phase, now: CACurrentMediaTime()), forKey: "breathing")
        }
    }
}
