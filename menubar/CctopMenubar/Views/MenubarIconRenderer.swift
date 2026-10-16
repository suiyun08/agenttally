import AppKit

/// Renders the menubar item as per-agent groups of session dots (see `StatusDotLayout`) on a
/// small translucent pill, so the dots stay readable over any wallpaper showing through the
/// menu bar. With nothing worth a look it becomes a short monochrome template line.
///
/// With `breathing`, the dots that wait on the user are drawn as rings only; `MenubarIndicator`
/// lays a fading fill over each one (see `breathingSpots`).
@MainActor
enum MenubarIconRenderer {
    /// Where a breathing dot sits in the image, and where in its breath it starts.
    struct BreathingSpot: Equatable {
        let rect: NSRect
        let dot: StatusDotGroup.Dot
        let phase: Double
    }

    /// The status item is 22 points tall; the pill takes 18 of them.
    static let height: CGFloat = 20
    private static let emptyLine = NSSize(width: 16, height: 3)
    private static let ringWidth: CGFloat = 1.4
    /// Space between the pill's edge and the first mark or last dot.
    static let pillPadding: CGFloat = 7

    static func render(counts: StatusCounts, breathing: Bool = false) -> NSImage {
        guard !counts.dotGroups.isEmpty else { return emptyImage() }
        let layout = StatusDotLayout(groups: counts.dotGroups, metrics: .menubar)
        let size = NSSize(width: layout.width + pillPadding * 2, height: height)
        let image = NSImage(size: size, flipped: false) { rect in
            // AppKit makes the status item's effective appearance current here,
            // so one live image follows menu-bar light/dark changes immediately.
            let appearance: NSAppearance = NSAppearance.current
            drawPill(in: rect, appearance: appearance)
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current?.cgContext.translateBy(x: pillPadding, y: 0)
            draw(layout, metrics: .menubar, appearance: appearance, breathing: breathing)
            return true
        }
        image.isTemplate = false
        return image
    }

    /// The breathing dots of `render(counts:breathing: true)`, in image coordinates.
    static func breathingSpots(counts: StatusCounts) -> [BreathingSpot] {
        guard !counts.dotGroups.isEmpty else { return [] }
        let metrics = StatusDotMetrics.menubar
        let layout = StatusDotLayout(groups: counts.dotGroups, metrics: metrics)
        return layout.dotSpots.filter(\.dot.breathes).map { spot in
            BreathingSpot(
                rect: NSRect(
                    x: pillPadding + spot.xPos, y: (height - metrics.dotDiameter) / 2,
                    width: metrics.dotDiameter, height: metrics.dotDiameter
                ),
                dot: spot.dot,
                phase: spot.phase
            )
        }
    }

    /// A dot's color: the theme's status color, or the system accent for an unread result.
    static func color(for dot: StatusDotGroup.Dot, appearance: NSAppearance) -> NSColor {
        switch dot {
        case .unreadDone: return .controlAccentColor
        case .permission, .attention, .working: return StatusColors.color(for: dot.segmentKind, appearance: appearance)
        }
    }

    /// A translucent capsule with a hairline rim, like the panel's own buttons: frosted white on a
    /// light menu bar and smoked on a dark one, so each status palette sits on the kind of
    /// background it was picked for, whatever the wallpaper behind the menu bar.
    private static func drawPill(in rect: NSRect, appearance: NSAppearance) {
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let pill = rect.insetBy(dx: 0.5, dy: 1)
        let path = NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2)
        (isDark ? NSColor.black.withAlphaComponent(0.32) : NSColor.white.withAlphaComponent(0.6)).setFill()
        path.fill()
        (isDark ? NSColor.white.withAlphaComponent(0.16) : NSColor.black.withAlphaComponent(0.1)).setStroke()
        path.lineWidth = 0.75
        path.stroke()
    }

    private static func emptyImage() -> NSImage {
        let image = NSImage(size: NSSize(width: emptyLine.width, height: height), flipped: false) { _ in
            let rect = NSRect(
                x: 0, y: (height - emptyLine.height) / 2,
                width: emptyLine.width, height: emptyLine.height
            )
            NSColor.labelColor.setFill()
            NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func draw(
        _ layout: StatusDotLayout, metrics: StatusDotMetrics, appearance: NSAppearance, breathing: Bool
    ) {
        let midY = height / 2
        for item in layout.items {
            switch item {
            case .dot(let dot, let xPos):
                let rect = NSRect(
                    x: xPos, y: midY - metrics.dotDiameter / 2,
                    width: metrics.dotDiameter, height: metrics.dotDiameter
                )
                drawDot(dot, in: rect, appearance: appearance, hollow: breathing && dot.breathes)
            case .mark(let badge, let xPos, let width):
                let rect = NSRect(
                    x: xPos, y: midY - metrics.markHeight / 2,
                    width: width, height: metrics.markHeight
                )
                AgentMark.draw(badge, in: rect, ink: NSColor.labelColor.withAlphaComponent(0.55))
            case .overflow(let text, let xPos, _):
                let attributed = NSAttributedString(string: text, attributes: [
                    .font: metrics.overflowFont,
                    .foregroundColor: NSColor.secondaryLabelColor,
                ])
                let size = attributed.size()
                attributed.draw(at: NSPoint(x: xPos, y: midY - size.height / 2))
            }
        }
    }

    /// An unread result is a ring and any other dot is solid; a breathing dot is just its ring.
    private static func drawDot(_ dot: StatusDotGroup.Dot, in rect: NSRect, appearance: NSAppearance, hollow: Bool) {
        let color = color(for: dot, appearance: appearance)
        if hollow || dot == .unreadDone {
            color.setStroke()
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: ringWidth / 2, dy: ringWidth / 2))
            ring.lineWidth = ringWidth
            ring.stroke()
        } else {
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
        }
    }
}

extension StatusDotGroup.Dot {
    /// Filled dots reuse the status bar's theme colors.
    var segmentKind: StatusCounts.SegmentKind {
        switch self {
        case .permission: return .permission
        case .attention: return .attention
        case .working: return .working
        case .unreadDone: return .idle
        }
    }
}
