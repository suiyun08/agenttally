import AppKit

/// Renders the menubar item as per-agent groups of session dots (see `StatusDotLayout`).
/// With nothing worth a look it becomes a short monochrome template line.
@MainActor
enum MenubarIconRenderer {
    private static let height: CGFloat = 18
    private static let emptyLine = NSSize(width: 14, height: 3)
    private static let ringWidth: CGFloat = 1.2

    static func render(counts: StatusCounts) -> NSImage {
        guard !counts.dotGroups.isEmpty else { return emptyImage() }
        let layout = StatusDotLayout(groups: counts.dotGroups, metrics: .menubar)
        let image = NSImage(size: NSSize(width: max(layout.width, 1), height: height), flipped: false) { _ in
            // AppKit makes the status item's effective appearance current here,
            // so one live image follows menu-bar light/dark changes immediately.
            draw(layout, metrics: .menubar, appearance: NSAppearance.current)
            return true
        }
        image.isTemplate = false
        return image
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

    private static func draw(_ layout: StatusDotLayout, metrics: StatusDotMetrics, appearance: NSAppearance) {
        let midY = height / 2
        for item in layout.items {
            switch item {
            case .dot(let dot, let xPos):
                let rect = NSRect(
                    x: xPos, y: midY - metrics.dotDiameter / 2,
                    width: metrics.dotDiameter, height: metrics.dotDiameter
                )
                drawDot(dot, in: rect, appearance: appearance)
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

    private static func drawDot(_ dot: StatusDotGroup.Dot, in rect: NSRect, appearance: NSAppearance) {
        switch dot {
        case .unreadDone:
            NSColor.controlAccentColor.setStroke()
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: ringWidth / 2, dy: ringWidth / 2))
            ring.lineWidth = ringWidth
            ring.stroke()
        case .permission, .attention, .working:
            StatusColors.color(for: dot.segmentKind, appearance: appearance).setFill()
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
