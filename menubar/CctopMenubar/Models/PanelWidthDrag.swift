import AppKit

/// The side edge a width drag holds; the opposite edge stays put.
enum PanelResizeEdge: Equatable {
    case leading
    case trailing
}

/// Geometry for dragging the panel's side edges to change its width.
enum PanelWidthDrag {
    /// Width of the grab zone inside each side edge.
    static let edgeZone: CGFloat = 5

    /// The edge under a window-space x position, if any.
    static func edge(atX xPos: CGFloat, panelWidth: CGFloat) -> PanelResizeEdge? {
        if xPos <= edgeZone { return .leading }
        if xPos >= panelWidth - edgeZone { return .trailing }
        return nil
    }

    /// The frame while dragging: follows the pointer within the presets' range, and the moving
    /// edge stops short of the screen's visible edge.
    static func frame(
        from start: NSRect, edge: PanelResizeEdge, deltaX: CGFloat, visible: NSRect? = nil
    ) -> NSRect {
        let proposed = edge == .leading ? start.width - deltaX : start.width + deltaX
        var widest = PanelWidth.range.upperBound
        if let visible {
            let room = edge == .leading
                ? start.maxX - (visible.minX + PanelPositioning.margin)
                : visible.maxX - PanelPositioning.margin - start.minX
            widest = max(PanelWidth.range.lowerBound, min(widest, room))
        }
        let width = min(max(proposed, PanelWidth.range.lowerBound), widest)
        return frame(start, holding: edge, width: width)
    }

    /// The frame a released drag settles on: the nearest preset, same edge held.
    static func settled(from frame: NSRect, edge: PanelResizeEdge) -> (frame: NSRect, width: PanelWidth) {
        let preset = PanelWidth.nearest(to: frame.width)
        return (self.frame(frame, holding: edge, width: CGFloat(preset.rawValue)), preset)
    }

    private static func frame(_ frame: NSRect, holding edge: PanelResizeEdge, width: CGFloat) -> NSRect {
        let originX = edge == .leading ? frame.maxX - width : frame.minX
        return NSRect(x: originX, y: frame.minY, width: width, height: frame.height)
    }
}

/// Side-edge resize state the panel content draws from: the width it follows during a drag,
/// and which edge shows its grip.
final class PanelResizeState: ObservableObject {
    /// The width during a drag; nil otherwise.
    @Published var width: CGFloat?
    @Published var hoveredEdge: PanelResizeEdge?
    @Published var draggingEdge: PanelResizeEdge?

    /// The edge whose grip shows: the one being dragged, else the one under the pointer.
    var gripEdge: PanelResizeEdge? { draggingEdge ?? hoveredEdge }
}
