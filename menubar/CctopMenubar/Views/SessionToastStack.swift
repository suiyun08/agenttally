import AppKit
import SwiftUI

/// Something in the floating notices' window: a session's notice, or the "N more" under them.
enum SessionToastItem: Hashable {
    case notice(String)
    case overflow
}

/// The floating notices' window's content. It takes every click on a notice itself instead of
/// handing it on to buttons, since the window never becomes key: a click opens the notice, or
/// closes it on its close button, and the scroll wheel scrolls a stack too long for the screen.
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
    /// The scroll wheel moved over a notice, by this many points (content following the finger).
    var onScroll: (CGFloat) -> Void = { _ in }
    /// The pointer came onto the notices, or left them; held still while it rested on them, they
    /// may re-sort once it leaves.
    var onPointerEntered: () -> Void = {}
    var onPointerLeft: () -> Void = {}
    /// Off while the notices fade away, so nothing on its way out takes a click.
    var takesClicks = true
    private(set) var items: [SessionToastItem: NSView] = [:]

    /// What a press would do, kept until it is let go.
    private var pressed: Action?

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

    override func mouseEntered(with event: NSEvent) {
        onPointerEntered()
    }

    override func mouseExited(with event: NSEvent) {
        onPointerLeft()
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 10
        onScroll(delta)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        action(at: convert(point, from: superview)) == nil ? nil : self
    }

    override func mouseDown(with event: NSEvent) {
        pressed = action(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressed = nil }
        // A click counts where it was let go too, so pressing one notice and letting go over
        // another does nothing.
        if let pressed, pressed == action(at: convert(event.locationInWindow, from: nil)) {
            onAction(pressed)
        }
    }
}

/// The floating notices' one window: the floating indicator's glass behind each notice, on every
/// desktop and over full-screen apps, never taking keyboard focus, drawn dark with white text as
/// the panel is. Sharing it keeps the notices together: when a notice goes, those after it slide
/// up to close the gap, and a stack too long for the screen shows the part that fits.
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
    private var growsDown = true
    private var isHiding = false
    /// Counts changes, so the tail of an animation does not undo a newer change.
    private var generation = 0

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        // The glass draws its own edge, as on the floating indicator. A window shadow would trace
        // every notice with a dark line over light windows, and a light one over dark windows.
        hasShadow = false
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

    /// Where `item` is going on screen, or is, once it has stopped moving.
    func screenFrame(of item: SessionToastItem) -> NSRect? {
        guard let view = stack.items[item] else { return nil }
        return convertToScreen(stack.convert(view.frame, to: nil))
    }

    /// Shows exactly `entries`, each at its frame: new ones fade in, gone ones fade out, and the
    /// rest slide to their new places, all within one window that fits around them, or within
    /// `viewport`, which clips a stack too long for the screen. Without `animated`, as while
    /// scrolling, everything moves at once.
    func show(_ entries: [Entry], growsDown: Bool, viewport: NSRect? = nil, animated: Bool = true) {
        guard !entries.isEmpty else { return hideAll() }
        generation += 1
        let target = viewport ?? entries.reduce(NSRect.null) { $0.union($1.frame) }
        let wasShown = isVisible && !isHiding
        // Kept in place, the stack's starting edge stays put and the window only grows or
        // shrinks away from it, which moves nothing on screen.
        let keepsStart = wasShown && growsDown == self.growsDown
            && Self.start(of: frame, growsDown: growsDown) == Self.start(of: target, growsDown: growsDown)
        self.growsDown = growsDown
        isHiding = false
        stack.takesClicks = true
        let gone = stack.items.keys.filter { item in !entries.contains { $0.item == item } }
        gone.forEach(fadeOut)
        let span = keepsStart && animated ? frame.union(target) : target
        if frame != span { setFrame(span, display: false) }
        let placed = place(entries, in: span, fadingIn: wasShown && animated)
        var moves = placed.moves
        let arrivals = placed.arrivals
        if !keepsStart || !animated, !moves.isEmpty {
            for move in moves {
                move.view.layer?.removeAllAnimations()
                move.view.frame = move.frame
            }
            moves = []
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
            guard let self, self.generation == current else { return }
            if self.frame != target { self.setFrame(target, display: true) }
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
