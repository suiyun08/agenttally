import AppKit
import SwiftUI

/// Something in the floating notices' window: a session's notice, or the "N more" under them.
enum SessionToastItem: Hashable {
    case notice(String)
    case overflow
}

/// The floating notices' window's content. It takes every click on a notice itself instead of
/// handing it on to buttons, since the window never becomes key: a press that moves drags the
/// window, and one that does not opens the notice, or closes it on its close button.
/// Around the notices the mouse falls through to whatever is behind.
final class SessionToastStackView: NSView {
    enum Action: Equatable {
        case open(String)
        case close(String)
        case overflow
    }

    /// The square in a notice's top-right corner where a click closes it: the close button and a
    /// little around it, clear of the status label and the message beside and below it.
    static let closeZone: CGFloat = 26

    var onAction: (Action) -> Void = { _ in }
    var onDragEnded: () -> Void = {}
    /// The pointer left the notices; held still while it rested on them, they may now re-sort.
    var onPointerLeft: () -> Void = {}
    /// Off while the notices fade away, so nothing on its way out takes a click.
    var takesClicks = true
    private(set) var items: [SessionToastItem: NSView] = [:]

    private struct Press {
        let start: NSPoint
        let windowOrigin: NSPoint
        let action: Action?
    }

    private var press: Press?
    private var dragging = false

    /// Whether the user is dragging the stack. A drag whose release never arrived ends once the
    /// button is up, so it cannot hold the notices still for good.
    var isDragging: Bool { dragging && NSEvent.pressedMouseButtons & 1 != 0 }

    func add(_ view: NSView, for item: SessionToastItem) {
        items[item] = view
        addSubview(view)
    }

    /// Stops `item` taking clicks and hands back its view, still on screen to fade out.
    func remove(_ item: SessionToastItem) -> NSView? {
        items.removeValue(forKey: item)
    }

    func removeAll() {
        subviews.forEach { $0.removeFromSuperview() }
        items = [:]
    }

    func action(at point: NSPoint) -> Action? {
        guard takesClicks, let hit = items.first(where: { $0.value.frame.contains(point) }) else { return nil }
        switch hit.key {
        case .overflow:
            return .overflow
        case .notice(let id):
            let frame = hit.value.frame
            let corner = NSRect(
                x: frame.maxX - Self.closeZone, y: frame.maxY - Self.closeZone,
                width: Self.closeZone, height: Self.closeZone
            )
            return corner.contains(point) ? .close(id) : .open(id)
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard trackingAreas.isEmpty else { return }
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil
        ))
    }

    override func mouseExited(with event: NSEvent) {
        onPointerLeft()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        action(at: convert(point, from: superview)) == nil ? nil : self
    }

    override func mouseDown(with event: NSEvent) {
        if dragging { endDrag() }
        press = Press(
            start: NSEvent.mouseLocation, windowOrigin: window?.frame.origin ?? .zero,
            action: action(at: convert(event.locationInWindow, from: nil))
        )
    }

    override func mouseDragged(with event: NSEvent) {
        guard let press, let window else { return }
        let location = NSEvent.mouseLocation
        if !dragging, FloatingIndicatorPlacement.isDrag(from: press.start, to: location) { dragging = true }
        guard dragging else { return }
        window.setFrameOrigin(NSPoint(
            x: press.windowOrigin.x + location.x - press.start.x, y: press.windowOrigin.y + location.y - press.start.y
        ))
    }

    override func mouseUp(with event: NSEvent) {
        guard let press else { return }
        self.press = nil
        if dragging { return endDrag() }
        // A click counts where it was let go too, so pressing one notice and letting go over
        // another does nothing.
        if let action = press.action, action == self.action(at: convert(event.locationInWindow, from: nil)) {
            onAction(action)
        }
    }

    private func endDrag() {
        dragging = false
        onDragEnded()
    }
}

/// The floating notices' one window: the floating indicator's glass behind each notice, on every
/// desktop and over full-screen apps, never taking keyboard focus, drawn dark with white text as
/// the panel is. Sharing it keeps the notices together: the stack drags as one, and when a notice
/// goes, those after it slide up to close the gap.
final class SessionToastStackWindow: NSPanel {
    struct Entry {
        let item: SessionToastItem
        /// Where it goes on screen.
        let frame: NSRect
        let cornerRadius: CGFloat
        let content: AnyView
    }

    let stack = SessionToastStackView()
    private var hosts: [SessionToastItem: NSHostingView<AnyView>] = [:]
    /// The item nearest the stack's start: where the user dropped the stack is where it is.
    private var first: SessionToastItem?
    private var growsDown = true
    private var isHiding = false
    /// Counts changes, so the tail of an animation does not undo a newer change.
    private var generation = 0

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        appearance = NSAppearance(named: .darkAqua)
        contentView = stack
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// The first notice's frame on screen, wherever the user has dragged it.
    var firstFrame: NSRect? { first.flatMap(screenFrame(of:)) }

    /// Where `item` is going on screen, or is, once it has stopped moving.
    func screenFrame(of item: SessionToastItem) -> NSRect? {
        guard let view = stack.items[item] else { return nil }
        return convertToScreen(stack.convert(view.frame, to: nil))
    }

    /// Shows exactly `entries`, each at its frame: new ones fade in, gone ones fade out, and the
    /// rest slide to their new places, all within one window that fits around them.
    func show(_ entries: [Entry], growsDown: Bool) {
        guard !entries.isEmpty else { return hideAll() }
        generation += 1
        let target = entries.reduce(NSRect.null) { $0.union($1.frame) }
        let wasShown = isVisible && !isHiding
        // Kept in place, the stack's starting edge stays put and the window only grows or
        // shrinks away from it, which moves nothing on screen.
        let keepsStart = wasShown && growsDown == self.growsDown
            && Self.start(of: frame, growsDown: growsDown) == Self.start(of: target, growsDown: growsDown)
        self.growsDown = growsDown
        isHiding = false
        stack.takesClicks = true
        first = entries.first?.item
        let gone = stack.items.keys.filter { item in !entries.contains { $0.item == item } }
        gone.forEach(fadeOut)
        let span = keepsStart ? frame.union(target) : target
        if frame != span { setFrame(span, display: false) }
        let placed = place(entries, in: span, fadingIn: wasShown)
        var moves = placed.moves
        let arrivals = placed.arrivals
        if !keepsStart, !moves.isEmpty {
            for move in moves {
                move.view.layer?.removeAllAnimations()
                move.view.frame = move.frame
            }
            moves = []
            invalidateShadow()
        }
        if !isVisible {
            alphaValue = 0
            orderFrontRegardless()
        }
        guard !wasShown || !moves.isEmpty || !arrivals.isEmpty || !gone.isEmpty || span != target else { return }
        animate(moves: moves, arrivals: arrivals, fadingIn: !wasShown, thenFit: target)
    }

    func hideAll() {
        guard isVisible, !isHiding else { return }
        isHiding = true
        stack.takesClicks = false
        generation += 1
        let current = generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, self.generation == current else { return }
            self.orderOut(nil)
            self.stack.removeAll()
            self.hosts = [:]
            self.isHiding = false
        }
    }

    /// The stack's starting edge: the left end of its top when it grows down, of its bottom
    /// when it grows up.
    private static func start(of frame: NSRect, growsDown: Bool) -> NSPoint {
        NSPoint(x: frame.minX, y: growsDown ? frame.maxY : frame.minY)
    }

    /// Updates each entry's content and returns where views must go: existing ones that moved,
    /// and new ones, which start a little toward the stack's start and faded out when
    /// `fadingIn`, or in place otherwise.
    private func place(
        _ entries: [Entry], in span: NSRect, fadingIn: Bool
    ) -> (moves: [(view: NSView, frame: NSRect)], arrivals: [(view: NSView, frame: NSRect)]) {
        // Pinned to the starting edge, so the window growing or shrinking leaves them still.
        let pin: NSView.AutoresizingMask = growsDown ? .minYMargin : .maxYMargin
        var moves: [(view: NSView, frame: NSRect)] = []
        var arrivals: [(view: NSView, frame: NSRect)] = []
        for entry in entries {
            let frame = entry.frame.offsetBy(dx: -span.minX, dy: -span.minY)
            if let view = stack.items[entry.item], let host = hosts[entry.item] {
                host.rootView = entry.content
                view.autoresizingMask = pin
                if view.frame != frame { moves.append((view, frame)) }
                continue
            }
            let host = NSHostingView(rootView: entry.content)
            host.sizingOptions = []
            hosts[entry.item] = host
            let view = SystemGlass.wrapping(host, cornerRadius: entry.cornerRadius, tint: PanelGlassTint.glassTint(for:))
            view.autoresizingMask = pin
            stack.add(view, for: entry.item)
            if fadingIn {
                view.frame = frame.offsetBy(dx: 0, dy: growsDown ? 8 : -8)
                view.alphaValue = 0
                arrivals.append((view, frame))
            } else {
                view.frame = frame
            }
        }
        return (moves, arrivals)
    }

    private func animate(
        moves: [(view: NSView, frame: NSRect)], arrivals: [(view: NSView, frame: NSRect)],
        fadingIn: Bool, thenFit target: NSRect
    ) {
        let current = generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            if fadingIn { animator().alphaValue = 1 }
            for move in moves { move.view.animator().frame = move.frame }
            for arrival in arrivals {
                arrival.view.animator().frame = arrival.frame
                arrival.view.animator().alphaValue = 1
            }
        } completionHandler: { [weak self] in
            // Mid-drag the window keeps its size; the drag's end lays the stack out afresh.
            guard let self, self.generation == current, !self.stack.isDragging else { return }
            if self.frame != target { self.setFrame(target, display: true) }
            self.invalidateShadow()
        }
    }

    private func fadeOut(_ item: SessionToastItem) {
        hosts[item] = nil
        guard let view = stack.remove(item) else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            view.animator().alphaValue = 0
        } completionHandler: {
            view.removeFromSuperview()
        }
    }
}
