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

/// "N more" under the visible notices; a click opens the panel.
struct SessionToastOverflowView: View {
    let count: Int

    var body: some View {
        Text("\(count) more")
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
    /// The notices showing now, in order, held while the pointer rests on them.
    private var shownIDs: [String] = []
    private var appliedLimit = 0
    private var observer: NSObjectProtocol?

    private lazy var window: SessionToastStackWindow = {
        let window = SessionToastStackWindow()
        window.stack.onAction = { [weak self] action in self?.perform(action) }
        window.stack.onDragEnded = { [weak self] in self?.endDrag() }
        window.stack.onPointerLeft = { [weak self] in self?.layout() }
        return window
    }()

    init() {
        appliedLimit = Self.limit
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyLimit() }
        }
    }

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
        layout()
    }

    func close(_ id: String) {
        board.close(id)
        layout()
    }

    /// Puts the notices in place. Mid-drag it leaves them be: the drag's end lays them out
    /// where they landed. While the pointer rests on them they keep their order, so a click
    /// lands on the notice under it; they re-sort once it leaves.
    func layout() {
        guard !window.stack.isDragging else { return }
        guard !isSuppressed, FloatingIndicatorController.isEnabled, let start = stackStart() else {
            shownIDs = []
            return window.hideAll()
        }
        let count = SessionToastLayout.shownCount(
            limit: Self.limit, of: board.toasts.count, start: start.start, visible: start.visible
        )
        let pointerOn = window.isVisible && window.frame.contains(NSEvent.mouseLocation)
        let shown = board.visible(limit: count, holding: pointerOn ? shownIDs : [])
        shownIDs = shown.map(\.id)
        let overflow = board.waitingCount(besides: shown)
        let frames = SessionToastLayout.frames(
            count: shown.count, overflow: overflow > 0, start: start.start, visible: start.visible
        )
        window.show(entries(shown, overflow: overflow, frames: frames), growsDown: start.start.growsDown)
    }

    private func entries(
        _ shown: [SessionToast], overflow: Int, frames: SessionToastLayout.Frames
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
                content: AnyView(SessionToastOverflowView(count: overflow))
            ))
        }
        return entries
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
        case .overflow: onOverflow()
        }
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

    /// Remembers where the first notice landed, or goes back to following the indicator when it
    /// was dropped next to its place there.
    private func endDrag() {
        if let card = window.firstFrame { remember(firstCard: card) }
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
}
