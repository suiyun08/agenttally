import AppKit

/// One floating notice: a session that needs the user, shown under the floating indicator.
struct SessionToast: Equatable, Identifiable {
    /// The session's cctop session ID.
    let id: String
    let badge: AgentBadge
    let title: String
    let status: SessionStatus
    let message: String?
}

/// Which floating notices show: the sessions that would get a system notification, newest first.
/// They follow the same transitions — a new reason posts a session's notice, replacing an older
/// one, and a session that no longer needs the user loses it — and closing one hides it until the
/// session needs the user for a new reason. Sessions already waiting when the board starts get
/// none, as with system notifications.
struct SessionToastBoard: Equatable {
    static let maxVisible = 4

    private(set) var toasts: [SessionToast] = []

    var visible: [SessionToast] { Array(toasts.prefix(Self.maxVisible)) }
    var overflowCount: Int { max(0, toasts.count - Self.maxVisible) }

    mutating func apply(_ actions: [SessionNotificationAction], toast: (String) -> SessionToast?) {
        for action in actions {
            switch action {
            case .remove(let id):
                toasts.removeAll { $0.id == id }
            case .post(let id):
                toasts.removeAll { $0.id == id }
                if let posted = toast(id) { toasts.insert(posted, at: 0) }
            }
        }
    }

    /// Keeps each notice's title and message current, and drops any whose session no longer
    /// needs the user or is gone.
    mutating func refresh(_ toast: (String) -> SessionToast?) {
        toasts = toasts.compactMap { toast($0.id) }
    }

    mutating func dismiss(_ id: String) {
        toasts.removeAll { $0.id == id }
    }

    mutating func clear() {
        toasts = []
    }
}

/// Where the floating notices sit: stacked under the floating indicator, or over it when it sits
/// in the lower half of the screen, lined up with the indicator's edge nearest the screen's side.
enum SessionToastLayout {
    static let width: CGFloat = 300
    static let height: CGFloat = 56
    static let gap: CGFloat = 8
    static let overflowSize = NSSize(width: 120, height: 28)

    struct Frames: Equatable {
        let cards: [NSRect]
        let overflow: NSRect?
    }

    static func frames(count: Int, overflow: Bool, anchor: NSRect, visible: NSRect) -> Frames {
        let below = anchor.midY > visible.midY
        let alignsRight = anchor.midX > visible.midX
        var edge = below ? anchor.minY - gap : anchor.maxY + gap
        func place(_ size: NSSize) -> NSRect {
            let originX = alignsRight ? anchor.maxX - size.width : anchor.minX
            let originY = below ? edge - size.height : edge
            edge = below ? originY - gap : originY + size.height + gap
            let frame = NSRect(x: originX, y: originY, width: size.width, height: size.height)
            return frame.offsetBy(dx: horizontalShift(frame, into: visible), dy: 0)
        }
        let cards = (0..<count).map { _ in place(NSSize(width: width, height: height)) }
        return Frames(cards: cards, overflow: overflow ? place(overflowSize) : nil)
    }

    private static func horizontalShift(_ frame: NSRect, into visible: NSRect) -> CGFloat {
        if frame.minX < visible.minX { return visible.minX - frame.minX }
        if frame.maxX > visible.maxX { return visible.maxX - frame.maxX }
        return 0
    }
}
