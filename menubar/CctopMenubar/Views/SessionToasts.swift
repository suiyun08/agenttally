import AppKit
import SwiftUI

/// One floating notice: the agent's mark, the session's title, why it needs the user, and its
/// latest message. A click opens the session; the close button hides the notice.
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
        default:
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
/// never taking keyboard focus. Drawn dark, with white text, as the panel is.
final class SessionToastWindow: NSPanel {
    static let cornerRadius: CGFloat = 14

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
}

/// Shows the floating notices while the floating indicator is on, hides them while the panel is
/// open, and keeps them stacked against the indicator as it moves.
@MainActor
final class SessionToastController {
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

    func apply(_ actions: [SessionNotificationAction], toast: (String) -> SessionToast?) {
        guard FloatingIndicatorController.isEnabled else {
            if !board.toasts.isEmpty { board.clear() }
            return layout()
        }
        let before = board
        board.apply(actions, toast: toast)
        board.refresh(toast)
        if board != before { layout() }
    }

    func dismiss(_ id: String) {
        board.dismiss(id)
        layout()
    }

    func layout() {
        // Turning the indicator off forgets its notices; turned on again, it starts afresh.
        if !FloatingIndicatorController.isEnabled, !board.toasts.isEmpty { board.clear() }
        guard !isSuppressed, FloatingIndicatorController.isEnabled, let anchor = anchor(),
              let visible = NSScreen.screens.first(where: { $0.frame.intersects(anchor) })?.visibleFrame else {
            return hideAll()
        }
        let shown = board.visible
        let frames = SessionToastLayout.frames(
            count: shown.count, overflow: board.overflowCount > 0, anchor: anchor, visible: visible
        )
        for (id, window) in windows where !shown.contains(where: { $0.id == id }) {
            fadeOut(window)
            windows[id] = nil
        }
        for (toast, frame) in zip(shown, frames.cards) {
            let view = SessionToastView(
                toast: toast,
                onOpen: { [weak self] in self?.onOpen(toast.id) },
                onClose: { [weak self] in self?.dismiss(toast.id) }
            )
            if let window = windows[toast.id] {
                window.setContent(view)
                move(window, to: frame)
            } else {
                windows[toast.id] = show(SessionToastWindow(content: view, cornerRadius: SessionToastWindow.cornerRadius), at: frame)
            }
        }
        layoutOverflow(frame: frames.overflow)
    }

    private func layoutOverflow(frame: NSRect?) {
        guard let frame else {
            if let overflowWindow { fadeOut(overflowWindow) }
            overflowWindow = nil
            return
        }
        let view = SessionToastOverflowView(count: board.overflowCount) { [weak self] in self?.onOverflow() }
        if let overflowWindow {
            overflowWindow.setContent(view)
            move(overflowWindow, to: frame)
        } else {
            overflowWindow = show(SessionToastWindow(content: view, cornerRadius: frame.height / 2), at: frame)
        }
    }

    private func hideAll() {
        windows.values.forEach(fadeOut)
        windows = [:]
        if let overflowWindow { fadeOut(overflowWindow) }
        overflowWindow = nil
    }

    /// A new notice fades in while easing a few points out of the indicator's side.
    private func show(_ window: SessionToastWindow, at frame: NSRect) -> SessionToastWindow {
        let fromIndicator = (anchor()?.midY ?? frame.midY) > frame.midY ? 8.0 : -8.0
        window.setFrame(frame.offsetBy(dx: 0, dy: fromIndicator), display: false)
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
