import AppKit
import SwiftUI

/// One floating notice: the agent's mark, the session's title, its state, and what it is doing or
/// saying, with a close button in its corner. It only draws; `SessionToastStackView` takes its
/// clicks.
struct SessionToastView: View {
    let toast: SessionToast

    var body: some View {
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
        .overlay(alignment: .topTrailing) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.white.opacity(0.12)))
                .padding(7)
                .accessibilityLabel("Close")
        }
        .modifier(ToastBackground(cornerRadius: SessionToastLayout.cornerRadius))
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

/// The chip under the notices: "N more" shows them all; "Show less" goes back to the limit.
struct SessionToastOverflowView: View {
    /// Notices waiting behind the chip; nil once they all show.
    let count: Int?

    var body: some View {
        Group {
            if let count {
                Text("\(count) more")
            } else {
                Text("Show less")
            }
        }
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(Color.textPrimary)
        .frame(width: SessionToastLayout.overflowSize.width, height: SessionToastLayout.overflowSize.height)
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

/// Shows the floating notices for the floating indicator, lined up with it: while the pointer
/// rests on the indicator or on them, while pinned by a click on the indicator, while a session
/// waits for the user's permission or answer, and for a few seconds when a session newly needs
/// the user or finishes. They step aside while the panel is open. "N more" shows them all,
/// scrolling when they run past the screen.
@MainActor
final class SessionToastController {
    static let limitKey = "floatingNoticeLimit"
    /// Where an earlier version let the user drag the stack; cleared, as the stack now always
    /// follows the indicator.
    private static let retiredOriginKeys = ["floatingNoticeOriginX", "floatingNoticeOriginY"]

    var anchor: () -> NSRect? = { nil }
    var onOpen: (String) -> Void = { _ in }
    /// Asks the hover tracking to watch for the pointer leaving the indicator and the notices.
    var watchLeave: () -> Void = {}
    /// While the panel is open the notices step aside; it lists the same sessions.
    var isSuppressed = false {
        didSet { if isSuppressed != oldValue { layout() } }
    }

    private(set) var board = SessionToastBoard()
    private(set) var visibility = SessionToastVisibility()
    /// The notices showing now, in order, held while the pointer rests on them.
    private var shownIDs: [String] = []
    /// Showing every notice instead of the limit, scrolled this far when they run past the screen.
    private var expanded = false
    private var scrollOffset: CGFloat = 0
    private var appliedLimit = 0
    private var observer: NSObjectProtocol?
    private var desktopObserver: NSObjectProtocol?
    private var alertTimer: Timer?

    private lazy var window = makeWindow()

    init() {
        appliedLimit = Self.limit
        Self.retiredOriginKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyLimit() }
        }
        desktopObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.followDesktop() }
        }
    }

    private func makeWindow() -> SessionToastStackWindow {
        let window = SessionToastStackWindow()
        window.stack.onAction = { [weak self] action in self?.perform(action) }
        window.stack.onScroll = { [weak self] delta in self?.scroll(by: delta) }
        window.stack.onPointerEntered = { [weak self] in self?.pointerCameOn() }
        window.stack.onPointerLeft = { [weak self] in self?.layout() }
        return window
    }

    /// The notices' window is on every desktop, as the indicator's is, yet after hours of hiding
    /// and showing macOS has been seen to keep it on one desktop only. Showing while the user is
    /// on another desktop, it gives way to a fresh window, which joins every desktop.
    private func followDesktop() {
        guard window.isVisible, !window.isOnActiveSpace else { return }
        window.orderOut(nil)
        window = makeWindow()
        shownIDs = []
        layout(animated: false)
    }

    static var limit: Int {
        let stored = UserDefaults.standard.object(forKey: limitKey) as? Int ?? SessionToastBoard.defaultLimit
        return min(max(stored, SessionToastBoard.limitRange.lowerBound), SessionToastBoard.limitRange.upperBound)
    }

    /// The notices' frame on screen while they show.
    var visibleFrame: NSRect? {
        window.isVisible ? window.frame : nil
    }

    func update(_ candidates: [SessionToast]) {
        guard FloatingIndicatorController.isEnabled else {
            // Turned off, the indicator forgets its notices; turned on again, it starts afresh.
            if board != SessionToastBoard() {
                board.reset()
                visibility = SessionToastVisibility()
            }
            return layout()
        }
        let wasVisible = visibility.isVisible(now: Date())
        if board.update(candidates) { alert() }
        followWaiting(wasVisible: wasVisible)
    }

    func close(_ id: String) {
        let wasVisible = visibility.isVisible(now: Date())
        board.close(id)
        followWaiting(wasVisible: wasVisible)
    }

    /// Keeps the notices out while a notice waits for the user's permission or answer, and folds
    /// them back once none does.
    private func followWaiting(wasVisible: Bool) {
        visibility.setWaiting(Set(board.toasts.filter(\.waitsForUser).map(\.id)))
        if wasVisible, !visibility.isVisible(now: Date()) { return reasonEnded() }
        layout()
    }

    // MARK: - When they show

    /// A click on the floating indicator: pins the notices, or puts away notices that show for good.
    func toggle() {
        visibility.toggle()
        if !visibility.isVisible(now: Date()) { collapse() }
        layout()
    }

    func pointerLeftIndicator() {
        visibility.pointerLeftIndicator()
    }

    func setPeeking(_ on: Bool) {
        visibility.setPeeking(on)
        if !visibility.isVisible(now: Date()) { collapse() }
        layout()
    }

    /// Shows the notices for a moment; the pointer resting on them keeps them out.
    private func alert() {
        let now = Date()
        visibility.alert(now: now)
        alertTimer?.invalidate()
        let duration = SessionToastVisibility.alertDuration + 0.05
        alertTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.reasonEnded() }
        }
    }

    /// The alert ran out, or no notice waits for the user any more.
    private func reasonEnded() {
        if pointerIsOn { return pointerCameOn() }
        if !visibility.isVisible(now: Date()) { collapse() }
        layout()
    }

    /// The pointer on the notices keeps them out as resting on the indicator does.
    private func pointerCameOn() {
        guard window.isVisible, !visibility.peeking else { return }
        visibility.setPeeking(true)
        watchLeave()
        layout()
    }

    private var pointerIsOn: Bool {
        let point = NSEvent.mouseLocation
        return [anchor(), visibleFrame].compactMap { $0 }.contains { $0.insetBy(dx: -2, dy: -2).contains(point) }
    }

    // MARK: - Laying them out

    /// Puts the notices in place. While the pointer rests on them they keep their order, so a
    /// click lands on the notice under it; they re-sort once it leaves.
    func layout(animated: Bool = true) {
        guard !isSuppressed, FloatingIndicatorController.isEnabled, visibility.isVisible(now: Date()),
              let start = stackStart() else {
            shownIDs = []
            return window.hideAll()
        }
        let total = board.toasts.count
        let pointerOn = window.isVisible && window.frame.contains(NSEvent.mouseLocation)
        let fitting = SessionToastLayout.shownCount(limit: Self.limit, of: total, start: start.start, visible: start.visible)
        if expanded, total <= fitting { collapse() }
        let held = pointerOn ? shownIDs : []
        let shown = expanded ? board.all(holding: held) : board.visible(limit: fitting, holding: held)
        shownIDs = shown.map(\.id)
        let waiting = board.waitingCount(besides: shown)
        var frames = SessionToastLayout.frames(
            count: shown.count, overflow: expanded || waiting > 0, start: start.start, visible: start.visible
        )
        var viewport: NSRect?
        if expanded {
            let room = SessionToastLayout.room(from: start.start, visible: start.visible)
            let overrun = max(0, SessionToastLayout.length(of: frames, start: start.start) - room)
            scrollOffset = min(max(0, scrollOffset), overrun)
            if overrun > 0 {
                frames = SessionToastLayout.scrolled(frames, by: scrollOffset, growsDown: start.start.growsDown)
                viewport = SessionToastLayout.viewport(
                    start: start.start, visible: start.visible, minX: frames.cards.first?.minX ?? start.start.point.x
                )
            }
        }
        window.show(
            entries(shown, chip: expanded ? nil : waiting, frames: frames),
            growsDown: start.start.growsDown, viewport: viewport, animated: animated
        )
    }

    private func entries(
        _ shown: [SessionToast], chip: Int?, frames: SessionToastLayout.Frames
    ) -> [SessionToastStackWindow.Entry] {
        var entries = zip(shown, frames.cards).map { toast, frame in
            SessionToastStackWindow.Entry(
                item: .notice(toast.id), frame: frame, cornerRadius: SessionToastLayout.cornerRadius,
                content: AnyView(SessionToastView(toast: toast))
            )
        }
        if let frame = frames.overflow {
            entries.append(SessionToastStackWindow.Entry(
                item: .overflow, frame: frame, cornerRadius: frame.height / 2,
                content: AnyView(SessionToastOverflowView(count: chip))
            ))
        }
        return entries
    }

    /// Scrolls a stack too long for the screen, the content following the finger.
    private func scroll(by delta: CGFloat) {
        guard expanded, let start = stackStart() else { return }
        scrollOffset += start.start.growsDown ? -delta : delta
        layout(animated: false)
    }

    private func collapse() {
        expanded = false
        scrollOffset = 0
    }

    /// A new limit from Settings shows at once.
    private func applyLimit() {
        guard Self.limit != appliedLimit else { return }
        appliedLimit = Self.limit
        layout()
    }

    private func perform(_ action: SessionToastStackView.Action) {
        switch action {
        case .open(let id): onOpen(id)
        case .close(let id): close(id)
        case .overflow:
            if expanded { collapse() } else { expanded = true }
            layout()
        }
    }

    /// Under the floating indicator, or over it when it sits low on the screen.
    private func stackStart() -> (start: SessionToastLayout.Start, visible: NSRect)? {
        guard let indicator = anchor(),
              let visible = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: indicator.midX, y: indicator.midY)) })?
                .visibleFrame else { return nil }
        return (SessionToastLayout.start(under: indicator, visible: visible), visible)
    }
}
