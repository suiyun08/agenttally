import AppKit
import SwiftUI

/// One floating notice: the agent's mark, the session's title, its state, and what it is doing or
/// saying. A click opens the session; the close button hides the notice.
struct SessionToastView: View {
    let toast: SessionToast
    let onOpen: () -> Void
    let onClose: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 10) {
                Image(nsImage: AgentMark.image(for: toast.badge, height: 18, ink: NSColor.white.withAlphaComponent(0.85)))
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(verbatim: toast.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        statusLabel
                    }
                    if let message = toast.message {
                        Text(verbatim: message)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }
                }
                .padding(.trailing, 16)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: SessionToastLayout.width, height: SessionToastLayout.height, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .padding(7)
            .accessibilityLabel("Close")
        }
        .modifier(ToastBackground(cornerRadius: SessionToastWindow.cornerRadius))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch toast.status {
        case .waitingPermission:
            label("Permission", dot: .statusPermission, text: .statusPermissionText)
        case .waitingInput:
            label("Needs Input", dot: .statusAttention, text: .statusAttentionText)
        case .needsAttention:
            label("Error", dot: .statusAttention, text: .statusAttentionText)
        case .working:
            label("Working", dot: .statusGreen, text: .statusWorkingText)
        case .compacting:
            label("Compacting", dot: .statusGreen, text: .statusWorkingText)
        case .background:
            label("Background", dot: .statusGreen.opacity(0.55), text: .statusWorkingText)
        case .done, .idle:
            label("Done", dot: .accentColor, text: .textPrimary)
        }
    }

    private func label(_ text: LocalizedStringKey, dot: Color, text color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(dot).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)
        }
        .fixedSize()
    }
}

/// "N more" under the visible notices; a click opens the panel.
struct SessionToastOverflowView: View {
    let count: Int
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            Text("\(count) more")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.textPrimary)
                .frame(width: SessionToastLayout.overflowSize.width, height: SessionToastLayout.overflowSize.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(ToastBackground(cornerRadius: SessionToastLayout.overflowSize.height / 2))
    }
}

/// The theme's solid color behind a notice when there is no `SystemGlass` to sit on.
private struct ToastBackground: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if SystemGlass.isAvailable {
            content
        } else {
            content.background(
                Color.panelBackground.opacity(0.92),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        }
    }
}

/// A hosting view that takes the first click: the notices' windows never become key.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A notice's window: the floating indicator's glass, on every desktop and over full-screen apps,
/// never taking keyboard focus. Drawn dark, with white text, as the panel is. A press that moves
/// drags the whole stack; one that does not is a click for the notice's buttons.
final class SessionToastWindow: NSPanel {
    static let cornerRadius: CGFloat = 14

    var onDragBegan: (() -> Void)?
    var onDragChanged: ((CGVector) -> Void)?
    var onDragEnded: (() -> Void)?

    private let host: NSHostingView<AnyView>

    init(content: some View, cornerRadius: CGFloat) {
        let host = FirstClickHostingView(rootView: AnyView(content))
        host.sizingOptions = []
        self.host = host
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
        contentView = SystemGlass.wrapping(host, cornerRadius: cornerRadius, tint: PanelGlassTint.glassTint(for:))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func setContent(_ content: some View) {
        host.rootView = AnyView(content)
    }

    override func sendEvent(_ event: NSEvent) {
        guard event.type == .leftMouseDown else { return super.sendEvent(event) }
        let start = NSEvent.mouseLocation
        var dragging = false
        while let next = nextEvent(
            matching: [.leftMouseDragged, .leftMouseUp], until: .distantFuture, inMode: .eventTracking, dequeue: true
        ) {
            if next.type == .leftMouseUp {
                if dragging {
                    onDragEnded?()
                } else {
                    // Not a drag: hand the press to the notice's buttons, with its release
                    // waiting for them at the front of the queue.
                    NSApp.postEvent(next, atStart: true)
                    super.sendEvent(event)
                }
                return
            }
            let location = NSEvent.mouseLocation
            if !dragging, FloatingIndicatorPlacement.isDrag(from: start, to: location) {
                dragging = true
                onDragBegan?()
            }
            if dragging { onDragChanged?(CGVector(dx: location.x - start.x, dy: location.y - start.y)) }
        }
    }
}

/// Shows the floating notices while the floating indicator is on, hides them while the panel is
/// open, and keeps them stacked against the indicator, or where the user dragged them.
@MainActor
final class SessionToastController {
    static let limitKey = "floatingNoticeLimit"
    private static let originXKey = "floatingNoticeOriginX"
    private static let originYKey = "floatingNoticeOriginY"
    /// Dropped this close to its place under the indicator, the stack goes back to following it.
    private static let reattachDistance: CGFloat = 30

    var anchor: () -> NSRect? = { nil }
    var onOpen: (String) -> Void = { _ in }
    var onOverflow: () -> Void = {}
    /// While the panel is open the notices step aside; it lists the same sessions.
    var isSuppressed = false {
        didSet { if isSuppressed != oldValue { layout() } }
    }

    private(set) var board = SessionToastBoard()
    private var windows: [String: SessionToastWindow] = [:]
    private var overflowWindow: SessionToastWindow?
    private var dragOrigins: [NSWindow: NSPoint] = [:]

    static var limit: Int {
        let stored = UserDefaults.standard.object(forKey: limitKey) as? Int ?? SessionToastBoard.defaultLimit
        return min(max(stored, SessionToastBoard.limitRange.lowerBound), SessionToastBoard.limitRange.upperBound)
    }

    func update(_ candidates: [SessionToast]) {
        if FloatingIndicatorController.isEnabled {
            board.update(candidates)
        } else if board != SessionToastBoard() {
            // Turned off, the indicator forgets its notices; turned on again, it starts afresh.
            board.reset()
        }
        guard dragOrigins.isEmpty else { return }
        layout()
    }

    func close(_ id: String) {
        board.close(id)
        layout()
    }

    func layout() {
        guard !isSuppressed, FloatingIndicatorController.isEnabled, let start = stackStart() else { return hideAll() }
        let limit = Self.limit
        let shown = board.visible(limit: limit)
        let frames = SessionToastLayout.frames(
            count: shown.count, overflow: board.overflowCount(limit: limit) > 0, start: start.start, visible: start.visible
        )
        for (id, window) in windows where !shown.contains(where: { $0.id == id }) {
            fadeOut(window)
            windows[id] = nil
        }
        for (toast, frame) in zip(shown, frames.cards) {
            let view = SessionToastView(
                toast: toast,
                onOpen: { [weak self] in self?.onOpen(toast.id) },
                onClose: { [weak self] in self?.close(toast.id) }
            )
            if let window = windows[toast.id] {
                window.setContent(view)
                move(window, to: frame)
            } else {
                windows[toast.id] = show(makeWindow(view, cornerRadius: SessionToastWindow.cornerRadius), at: frame)
            }
        }
        layoutOverflow(frame: frames.overflow, limit: limit)
    }

    // MARK: - Where the stack starts

    /// Where the user left the stack, while that spot is still on a screen; otherwise under the
    /// floating indicator.
    private func stackStart() -> (start: SessionToastLayout.Start, visible: NSRect)? {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.originXKey) != nil, defaults.object(forKey: Self.originYKey) != nil {
            let card = NSRect(
                x: defaults.double(forKey: Self.originXKey), y: defaults.double(forKey: Self.originYKey),
                width: SessionToastLayout.width, height: SessionToastLayout.height
            )
            if let visible = visibleFrame(containing: NSPoint(x: card.midX, y: card.midY)) {
                return (SessionToastLayout.start(forFirstCard: card, visible: visible), visible)
            }
        }
        guard let indicator = anchor(), let visible = visibleFrame(containing: NSPoint(x: indicator.midX, y: indicator.midY))
        else { return nil }
        return (SessionToastLayout.start(under: indicator, visible: visible), visible)
    }

    private func visibleFrame(containing point: NSPoint) -> NSRect? {
        NSScreen.screens.first { $0.frame.contains(point) }?.visibleFrame
    }

    // MARK: - Dragging the stack

    private func beginDrag() {
        var origins: [NSWindow: NSPoint] = [:]
        for window in Array(windows.values) + [overflowWindow].compactMap({ $0 }) {
            origins[window] = window.frame.origin
        }
        dragOrigins = origins
    }

    private func drag(by delta: CGVector) {
        for (window, origin) in dragOrigins {
            window.setFrameOrigin(NSPoint(x: origin.x + delta.dx, y: origin.y + delta.dy))
        }
    }

    /// Remembers where the first notice landed, or goes back to following the indicator when it
    /// was dropped next to its place there.
    private func endDrag() {
        dragOrigins = [:]
        if let first = board.visible(limit: Self.limit).first, let card = windows[first.id]?.frame {
            remember(firstCard: card)
        }
        layout()
    }

    private func remember(firstCard card: NSRect) {
        let defaults = UserDefaults.standard
        if let home = homeFrame(), hypot(card.minX - home.minX, card.maxY - home.maxY) < Self.reattachDistance {
            defaults.removeObject(forKey: Self.originXKey)
            defaults.removeObject(forKey: Self.originYKey)
        } else {
            defaults.set(card.minX, forKey: Self.originXKey)
            defaults.set(card.minY, forKey: Self.originYKey)
        }
    }

    /// The first notice's place under the floating indicator.
    private func homeFrame() -> NSRect? {
        guard let indicator = anchor(),
              let visible = visibleFrame(containing: NSPoint(x: indicator.midX, y: indicator.midY)) else { return nil }
        let start = SessionToastLayout.start(under: indicator, visible: visible)
        return SessionToastLayout.frames(count: 1, overflow: false, start: start, visible: visible).cards.first
    }

    // MARK: - Windows

    private func makeWindow(_ view: some View, cornerRadius: CGFloat) -> SessionToastWindow {
        let window = SessionToastWindow(content: view, cornerRadius: cornerRadius)
        window.onDragBegan = { [weak self] in self?.beginDrag() }
        window.onDragChanged = { [weak self] delta in self?.drag(by: delta) }
        window.onDragEnded = { [weak self] in self?.endDrag() }
        return window
    }

    private func layoutOverflow(frame: NSRect?, limit: Int) {
        guard let frame else {
            if let overflowWindow { fadeOut(overflowWindow) }
            overflowWindow = nil
            return
        }
        let view = SessionToastOverflowView(count: board.overflowCount(limit: limit)) { [weak self] in self?.onOverflow() }
        if let overflowWindow {
            overflowWindow.setContent(view)
            move(overflowWindow, to: frame)
        } else {
            overflowWindow = show(makeWindow(view, cornerRadius: frame.height / 2), at: frame)
        }
    }

    private func hideAll() {
        windows.values.forEach(fadeOut)
        windows = [:]
        if let overflowWindow { fadeOut(overflowWindow) }
        overflowWindow = nil
    }

    /// A new notice fades in while easing a few points out of the stack's starting side.
    private func show(_ window: SessionToastWindow, at frame: NSRect) -> SessionToastWindow {
        let growsDown = stackStart()?.start.growsDown ?? true
        window.setFrame(frame.offsetBy(dx: 0, dy: growsDown ? 8 : -8), display: false)
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(frame, display: true)
            window.animator().alphaValue = 1
        }
        return window
    }

    private func move(_ window: SessionToastWindow, to frame: NSRect) {
        guard window.frame != frame else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            window.animator().setFrame(frame, display: true)
        }
    }

    private func fadeOut(_ window: SessionToastWindow) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            window.animator().alphaValue = 0
        } completionHandler: {
            window.orderOut(nil)
        }
    }
}
