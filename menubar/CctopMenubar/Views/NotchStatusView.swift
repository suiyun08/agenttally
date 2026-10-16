import QuartzCore
import SwiftUI

struct NotchStatusView: View {
    let counts: StatusCounts
    var themeId: String = ""

    static let leadingPadding: CGFloat = 5
    static let trailingPadding: CGFloat = 2
    private static let emptyLineWidth: CGFloat = 14

    /// Width of the dots (or the empty line) for a pill whose content may not exceed `maxWidth`.
    static func contentWidth(for counts: StatusCounts, maxWidth: CGFloat) -> CGFloat {
        guard !counts.dotGroups.isEmpty else { return emptyLineWidth }
        return StatusDotLayout(groups: counts.dotGroups, metrics: .notch, maxWidth: maxWidth).width
    }

    var body: some View {
        Group {
            if counts.dotGroups.isEmpty {
                Capsule().fill(Color.white.opacity(0.52))
                    .frame(width: Self.emptyLineWidth, height: 3)
            } else {
                NotchStatusDots(
                    layout: StatusDotLayout(
                        groups: counts.dotGroups,
                        metrics: .notch,
                        maxWidth: NotchStatusController.maxContentWidth
                    ),
                    metrics: .notch
                )
            }
        }
        .frame(height: 11)
        .id(themeId)
        .padding(.leading, Self.leadingPadding)
        .padding(.trailing, Self.trailingPadding)
        .padding(.top, 4)
        .padding(.bottom, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.90))
        .clipShape(NotchTabShape(radius: 6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(counts.accessibilityLabel)
    }
}

/// The pill's dots. Dots waiting on the user breathe (see `DotBreathing`), redrawn on the
/// animation timeline only while one is shown and motion is allowed.
private struct NotchStatusDots: View {
    let layout: StatusDotLayout
    let metrics: StatusDotMetrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Entry {
        let item: StatusDotLayout.Item
        /// Set for a dot that breathes.
        let phase: Double?
    }

    var body: some View {
        let entries = Self.entries(for: layout)
        if reduceMotion || !entries.contains(where: { $0.phase != nil }) {
            dots(entries, time: nil)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { _ in
                dots(entries, time: CACurrentMediaTime())
            }
        }
    }

    /// Each layout item, with the breathing phase of a dot that breathes.
    private static func entries(for layout: StatusDotLayout) -> [Entry] {
        var spots = layout.dotSpots.makeIterator()
        return layout.items.map { item in
            guard case .dot = item, let spot = spots.next() else { return Entry(item: item, phase: nil) }
            return Entry(item: item, phase: spot.dot.breathes ? spot.phase : nil)
        }
    }

    private func dots(_ entries: [Entry], time: TimeInterval?) -> some View {
        ZStack(alignment: .leading) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                switch entry.item {
                case .dot(let dot, let xPos):
                    dotView(dot, fill: time.flatMap { time in entry.phase.map { DotBreathing.fill(at: time, phase: $0) } })
                        .frame(width: metrics.dotDiameter, height: metrics.dotDiameter)
                        .offset(x: xPos)
                case .mark(let badge, let xPos, let width):
                    Image(nsImage: AgentMark.image(
                        for: badge, height: metrics.markHeight, ink: NSColor.white.withAlphaComponent(0.6)
                    ))
                    .frame(width: width, height: metrics.markHeight)
                    .offset(x: xPos)
                case .overflow(let text, let xPos, let width):
                    Text(verbatim: text)
                        .font(Font(metrics.overflowFont as CTFont))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .fixedSize()
                        .frame(width: width, alignment: .leading)
                        .offset(x: xPos)
                }
            }
        }
        .frame(width: layout.width, height: 11, alignment: .leading)
    }

    /// `fill` is set for a breathing dot: its ring, with the fill faded in that far.
    @ViewBuilder
    private func dotView(_ dot: StatusDotGroup.Dot, fill: Double?) -> some View {
        let color = dot == .unreadDone ? Color.accentColor : StatusColors.notchColor(for: dot.segmentKind)
        if let fill {
            ZStack {
                Circle().strokeBorder(color, lineWidth: 1.1)
                Circle().fill(color).opacity(fill)
            }
        } else if dot == .unreadDone {
            Circle().strokeBorder(color, lineWidth: 1.1)
        } else {
            Circle().fill(color)
        }
    }
}

/// Notch tab shape: flat top and right edge (meets the notch), rounded bottom-left corner only.
private struct NotchTabShape: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.minX, y: rect.maxY - radius),
            radius: radius
        )
        path.closeSubpath()
        return path
    }
}

#Preview("Mixed") {
    NotchStatusView(counts: StatusCounts(permission: 1, attention: 1, working: 2, idle: 1))
        .padding()
        .background(Color.black)
}

#Preview("Needs permission") {
    NotchStatusView(counts: StatusCounts(permission: 2, attention: 0, working: 1, idle: 0))
        .padding()
        .background(Color.black)
}

#Preview("All working") {
    NotchStatusView(counts: StatusCounts(permission: 0, attention: 0, working: 4, idle: 0))
        .padding()
        .background(Color.black)
}

#Preview("All idle") {
    NotchStatusView(counts: StatusCounts(permission: 0, attention: 0, working: 0, idle: 3))
        .padding()
        .background(Color.black)
}

#Preview("1 attention in 10 (min width)") {
    NotchStatusView(counts: StatusCounts(permission: 0, attention: 1, working: 7, idle: 2))
        .padding()
        .background(Color.black)
}

#Preview("1 permission in 20 (extreme squeeze)") {
    NotchStatusView(counts: StatusCounts(permission: 1, attention: 0, working: 19, idle: 0))
        .padding()
        .background(Color.black)
}

#Preview("No sessions") {
    NotchStatusView(counts: StatusCounts(permission: 0, attention: 0, working: 0, idle: 0))
        .padding()
        .background(Color.black)
}
