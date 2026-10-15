import AppKit

/// Keeps a dragged panel on screen and holds it against a screen edge it comes near, while the
/// drag is still going, so the user sees where it will land.
enum PanelSnap {
    /// How close a panel edge has to come to a screen edge before it sticks to it.
    static let threshold: CGFloat = 20
    /// The gap left between the panel and a side or bottom screen edge it sticks to.
    static let gap: CGFloat = 8

    /// The screen a drag is on: the one under the pointer, else the one the panel overlaps most.
    static func screen(pointer: NSPoint?, frame: NSRect, in screens: [ScreenLayout]) -> ScreenLayout? {
        if let pointer, let idx = PanelPositioning.screenIndex(containing: pointer, in: screens) {
            return screens[idx]
        }
        return PanelPositioning.screenIndex(forPanelFrame: frame, in: screens).map { screens[$0] }
    }

    /// The frame while dragging: wherever the pointer takes it, never past the visible area.
    static func keptOnScreen(_ frame: NSRect, visible: NSRect) -> NSRect {
        var kept = frame
        kept.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        kept.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        return kept
    }

    /// Where the panel shows for a drag position: on screen, and against any screen edge within
    /// the threshold. The top sticks where the panel opens under the menu bar.
    static func settled(_ frame: NSRect, visible: NSRect) -> NSRect {
        var settled = keptOnScreen(frame, visible: visible)
        if settled.minX - visible.minX < threshold {
            settled.origin.x = visible.minX + gap
        } else if visible.maxX - settled.maxX < threshold {
            settled.origin.x = visible.maxX - gap - settled.width
        }
        if visible.maxY - settled.maxY < threshold {
            settled.origin.y = visible.maxY - PanelPositioning.margin - settled.height
        } else if settled.minY - visible.minY < threshold {
            settled.origin.y = visible.minY + gap
        }
        return settled
    }
}
