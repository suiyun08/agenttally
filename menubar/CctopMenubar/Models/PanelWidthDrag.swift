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

    /// How close the dragged width has to come to a preset before it glides onto it.
    static let snapDistance: CGFloat = 20
    /// A width change bigger than this glides; smaller ones just follow the pointer.
    static let glideThreshold: CGFloat = 4

    /// The frame while dragging: the width follows the pointer, and within `snapDistance` of a
    /// preset it takes the preset. The moving edge never passes the screen's visible edge, and a
    /// preset that would not fit there is never offered.
    static func frame(
        from start: NSRect, edge: PanelResizeEdge, deltaX: CGFloat, visible: NSRect? = nil
    ) -> NSRect {
        let proposed = edge == .leading ? start.width - deltaX : start.width + deltaX
        let widest = widestWidth(for: start, holding: edge, visible: visible)
        let pointerWidth = min(max(proposed, PanelWidth.range.lowerBound), widest)
        let preset = fittingPresets(widest: widest).first {
            abs(CGFloat($0.rawValue) - pointerWidth) <= snapDistance
        }
        return frame(start, holding: edge, width: preset.map { CGFloat($0.rawValue) } ?? pointerWidth)
    }

    /// The frame a released drag settles on: the nearest preset that fits, same edge held.
    static func settled(
        from frame: NSRect, edge: PanelResizeEdge, visible: NSRect? = nil
    ) -> (frame: NSRect, width: PanelWidth) {
        let widest = widestWidth(for: frame, holding: edge, visible: visible)
        let preset = fittingPresets(widest: widest)
            .min { abs(CGFloat($0.rawValue) - frame.width) < abs(CGFloat($1.rawValue) - frame.width) }
            ?? .standard
        return (self.frame(frame, holding: edge, width: CGFloat(preset.rawValue)), preset)
    }

    /// A point of the way from one frame to another; both hold the same edge, so it stays put.
    static func interpolated(from start: NSRect, to end: NSRect, progress: CGFloat) -> NSRect {
        NSRect(
            x: start.minX + (end.minX - start.minX) * progress,
            y: end.minY,
            width: start.width + (end.width - start.width) * progress,
            height: end.height
        )
    }

    private static func widestWidth(for frame: NSRect, holding edge: PanelResizeEdge, visible: NSRect?) -> CGFloat {
        guard let visible else { return PanelWidth.range.upperBound }
        let room = edge == .leading
            ? frame.maxX - (visible.minX + PanelPositioning.margin)
            : visible.maxX - PanelPositioning.margin - frame.minX
        return max(PanelWidth.range.lowerBound, min(PanelWidth.range.upperBound, room))
    }

    private static func fittingPresets(widest: CGFloat) -> [PanelWidth] {
        PanelWidth.allCases.filter { CGFloat($0.rawValue) <= widest }
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

/// Glides the panel to a width over a short ease-out, frame by frame, so the content and the
/// window move together. A new target mid-glide redirects it without restarting.
@MainActor
final class PanelWidthAnimator {
    static let duration: CFTimeInterval = 0.16

    private let apply: @MainActor (NSRect) -> Void
    private var timer: Timer?
    private var start = NSRect.zero
    private var startTime: CFTimeInterval = 0
    private var completion: (@MainActor () -> Void)?
    private(set) var target: NSRect?

    var isRunning: Bool { timer != nil }

    init(apply: @escaping @MainActor (NSRect) -> Void) {
        self.apply = apply
    }

    func glide(from start: NSRect, to target: NSRect, completion: (@MainActor () -> Void)? = nil) {
        cancel()
        self.start = start
        self.target = target
        self.completion = completion
        startTime = CACurrentMediaTime()
        // Common modes keep it running inside the drag's event-tracking loop.
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    func redirect(to target: NSRect) {
        self.target = target
    }

    /// Stops where it is, without running the completion.
    func cancel() {
        timer?.invalidate()
        timer = nil
        target = nil
        completion = nil
    }

    private func tick() {
        guard let target else { return }
        let linear = min(1, (CACurrentMediaTime() - startTime) / Self.duration)
        let eased = 1 - pow(1 - linear, 3)
        apply(PanelWidthDrag.interpolated(from: start, to: target, progress: CGFloat(eased)))
        guard linear >= 1 else { return }
        let completion = self.completion
        cancel()
        completion?()
    }
}
