import AppKit

@MainActor protocol FloatingPanelDelegate: AnyObject {
    func panelDidDrag(originX: CGFloat, topY: CGFloat)
    func panelDidRequestReset()
    func panelHoveredEdgeDidChange(_ edge: PanelResizeEdge?)
    func panelWidthDragDidBegin(edge: PanelResizeEdge)
    func panelWidthDragDidMove(to frame: NSRect)
    func panelWidthDragDidEnd(at frame: NSRect, edge: PanelResizeEdge)
}

class FloatingPanel: NSPanel {
    weak var panelDelegate: FloatingPanelDelegate?
    private var edgeTrackingArea: NSTrackingArea?
    private weak var edgeTrackingView: NSView?
    private var hoveredEdge: PanelResizeEdge?
    /// Height of the header drag zone (shared with HeaderView).
    private let headerDragHeight = AppChrome.headerHeight
    static let defaultCollectionBehavior: NSWindow.CollectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

    enum HeaderClickAction: Equatable {
        case resetPosition
        case drag
    }

    /// macOS chains clickCount (1, 2, 3, …) for stationary clicks within the
    /// double-click interval, so a click right after a double-click reset
    /// arrives as count 3. Routing it into the drag loop would let the reset
    /// animation's frame movement read as a user drag; re-triggering the
    /// idempotent reset is always the intended outcome for counts ≥ 2.
    static func headerClickAction(forClickCount count: Int) -> HeaderClickAction {
        count >= 2 ? .resetPosition : .drag
    }

    /// The frame can move under a stationary click — reset and resize run
    /// setFrame(animate: true) — and persisting that movement as a drag
    /// would resurrect the saved position a reset just cleared. Only a real
    /// mouse drag may persist.
    static func shouldPersistDrag(sawDragEvents: Bool, originMoved: Bool) -> Bool {
        sawDragEvents && originMoved
    }

    static func shouldPrimeKeyWindowBeforeMouseDown(isKeyWindow: Bool, isHeaderClick: Bool) -> Bool {
        !isKeyWindow && !isHeaderClick
    }

    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: backing,
            defer: flag
        )
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow
        collectionBehavior = Self.defaultCollectionBehavior
    }

    override var contentView: NSView? {
        didSet { installEdgeTracking() }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func orderFront(_ sender: Any?) {
        super.orderFront(sender)
        enableCursorRects()
        if let contentView { invalidateCursorRects(for: contentView) }
    }

    // MARK: - Header drag via tight event-tracking loop

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown,
           let edge = PanelWidthDrag.edge(atX: event.locationInWindow.x, panelWidth: frame.width) {
            handleWidthDrag(holding: edge)
            return
        }
        if event.type == .leftMouseDown {
            let headerClick = isInHeaderArea(event)
            if Self.shouldPrimeKeyWindowBeforeMouseDown(isKeyWindow: isKeyWindow, isHeaderClick: headerClick) {
                makeKey()
            }
            if headerClick {
                switch Self.headerClickAction(forClickCount: event.clickCount) {
                case .resetPosition:
                    panelDelegate?.panelDidRequestReset()
                case .drag:
                    handleHeaderDrag()
                }
                return
            }
        }
        super.sendEvent(event)
    }

    private func handleHeaderDrag() {
        let startLocation = NSEvent.mouseLocation
        let startOrigin = frame.origin
        var sawDragEvents = false
        let screens = NSScreen.screens.map(ScreenLayout.init)

        // Tight event-tracking loop — runs in eventTracking mode,
        // preventing SwiftUI layout passes from interleaving.
        while true {
            guard let event = nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp],
                until: .distantFuture,
                inMode: .eventTracking,
                dequeue: true
            ) else { continue }

            if event.type == .leftMouseUp { break }
            sawDragEvents = true

            let current = NSEvent.mouseLocation
            var next = frame
            next.origin = NSPoint(
                x: startOrigin.x + current.x - startLocation.x,
                y: startOrigin.y + current.y - startLocation.y
            )
            if let screen = PanelSnap.screen(pointer: current, frame: next, in: screens) {
                next = PanelSnap.keptOnScreen(next, visible: screen.visibleFrame)
            }
            setFrameOrigin(next.origin)
        }

        var landed = frame
        if sawDragEvents,
           let screen = PanelSnap.screen(pointer: NSEvent.mouseLocation, frame: frame, in: screens) {
            landed = PanelSnap.settled(frame, visible: screen.visibleFrame)
            if landed != frame { settle(at: landed) }
        }

        if Self.shouldPersistDrag(
            sawDragEvents: sawDragEvents,
            originMoved: landed.origin != startOrigin
        ) {
            panelDelegate?.panelDidDrag(originX: landed.origin.x, topY: landed.maxY)
        }
    }

    /// Glides the released panel against the screen edge it was dropped near.
    private func settle(at target: NSRect) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = PanelSnap.settleDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            animator().setFrame(target, display: true)
        }
    }

    // MARK: - Side-edge width drag

    private func handleWidthDrag(holding edge: PanelResizeEdge) {
        let startLocation = NSEvent.mouseLocation
        let startFrame = frame
        var current = startFrame
        NSCursor.resizeLeftRight.set()
        panelDelegate?.panelWidthDragDidBegin(edge: edge)

        while true {
            guard let event = nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp],
                until: .distantFuture,
                inMode: .eventTracking,
                dequeue: true
            ) else { continue }

            if event.type == .leftMouseUp { break }
            let next = PanelWidthDrag.frame(
                from: startFrame, edge: edge, deltaX: NSEvent.mouseLocation.x - startLocation.x,
                visible: screen?.visibleFrame
            )
            guard abs(next.width - current.width) >= 0.5 else { continue }
            current = next
            panelDelegate?.panelWidthDragDidMove(to: next)
        }

        panelDelegate?.panelWidthDragDidEnd(at: current, edge: edge)
        updateHoveredEdge(at: mouseLocationOutsideOfEventStream)
    }

    // MARK: - Side-edge hover

    /// Tracks the pointer even while cctop is in the background, which the panel always is:
    /// it never activates the app, so it never takes focus from the user's terminal.
    private func installEdgeTracking() {
        if let edgeTrackingArea { edgeTrackingView?.removeTrackingArea(edgeTrackingArea) }
        edgeTrackingArea = nil
        guard let contentView else { return }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        contentView.addTrackingArea(area)
        edgeTrackingArea = area
        edgeTrackingView = contentView
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateHoveredEdge(at: event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        guard event.trackingArea === edgeTrackingArea else { return }
        updateHoveredEdge(at: nil)
    }

    private func updateHoveredEdge(at location: NSPoint?) {
        let edge = location.flatMap { point -> PanelResizeEdge? in
            guard point.y >= 0, point.y <= frame.height else { return nil }
            return PanelWidthDrag.edge(atX: point.x, panelWidth: frame.width)
        }
        if edge != nil {
            // Re-assert on every move; content views may reset the pointer underneath.
            NSCursor.resizeLeftRight.set()
        } else if hoveredEdge != nil {
            NSCursor.arrow.set()
        }
        guard edge != hoveredEdge else { return }
        hoveredEdge = edge
        panelDelegate?.panelHoveredEdgeDidChange(edge)
    }

    private func isInHeaderArea(_ event: NSEvent) -> Bool {
        event.locationInWindow.y >= frame.height - headerDragHeight
    }
}
