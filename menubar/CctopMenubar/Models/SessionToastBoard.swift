import AppKit

/// One floating notice: a session that is working or needs the user, shown by the floating
/// indicator.
struct SessionToast: Equatable, Identifiable {
    enum Kind: Equatable {
        /// Working, compacting, or running background tasks.
        case working
        /// Waiting for permission, an answer, or after an error.
        case needsYou
        /// A finished turn the user has not read.
        case done
    }

    /// The session's cctop session ID.
    let id: String
    let kind: Kind
    let badge: AgentBadge
    let title: String
    let status: SessionStatus
    let message: String?
    let lastActivity: Date
}

/// Which floating notices show: every session that is working or needs the user, most recent
/// activity first, each until the user closes it or the session goes idle, is read, or ends.
///
/// A closed notice comes back when its session needs the user again — it starts waiting or
/// finishes — or starts new work after going idle; carrying on with the same work does not bring
/// it back. When the board starts, live sessions (working or waiting) show at once, but results
/// that finished earlier and wait unread do not, so they never flood the screen.
struct SessionToastBoard: Equatable {
    static let defaultLimit = 4
    static let limitRange = 1...10

    /// Every notice that shows, most recent activity first; `visible` caps it.
    private(set) var toasts: [SessionToast] = []
    private var closed: Set<String> = []
    private var lastKinds: [String: SessionToast.Kind] = [:]
    private var started = false

    func visible(limit: Int) -> [SessionToast] { Array(toasts.prefix(limit)) }
    func overflowCount(limit: Int) -> Int { max(0, toasts.count - limit) }

    /// Brings the notices in line with the sessions that are working or need the user now.
    mutating func update(_ candidates: [SessionToast]) {
        var kinds: [String: SessionToast.Kind] = [:]
        for candidate in candidates {
            kinds[candidate.id] = candidate.kind
            let before = lastKinds[candidate.id]
            if !started, candidate.kind == .done {
                closed.insert(candidate.id)
            } else if closed.contains(candidate.id), before != candidate.kind,
                      candidate.kind != .working || before == .done {
                // A new reason to look: it started waiting, finished, or took up new work after
                // finishing. Back to work after an answer is the same work.
                closed.remove(candidate.id)
            }
        }
        // A session that went idle, was read, or ended starts afresh next time.
        closed.formIntersection(kinds.keys)
        lastKinds = kinds
        started = true
        toasts = candidates
            .filter { !closed.contains($0.id) }
            .sorted { $0.lastActivity > $1.lastActivity }
    }

    mutating func close(_ id: String) {
        closed.insert(id)
        toasts.removeAll { $0.id == id }
    }

    /// Forgets everything, as when the floating indicator is turned off.
    mutating func reset() {
        self = SessionToastBoard()
    }
}

/// Where the floating notices sit: a stack lined up with its left edge, growing down from its top
/// when it starts in the upper half of the screen and up from its bottom in the lower half. It
/// starts under (or over) the floating indicator, or wherever the user dragged it.
enum SessionToastLayout {
    static let width: CGFloat = 300
    static let height: CGFloat = 56
    static let gap: CGFloat = 8
    static let overflowSize = NSSize(width: 120, height: 28)

    /// The stack's starting edge: the left end of its top edge when it grows down, of its bottom
    /// edge when it grows up.
    struct Start: Equatable {
        let point: NSPoint
        let growsDown: Bool
    }

    struct Frames: Equatable {
        let cards: [NSRect]
        let overflow: NSRect?
    }

    /// Hanging off the floating indicator, left edges aligned.
    static func start(under indicator: NSRect, visible: NSRect) -> Start {
        let growsDown = indicator.midY > visible.midY
        return Start(
            point: NSPoint(x: indicator.minX, y: growsDown ? indicator.minY - gap : indicator.maxY + gap),
            growsDown: growsDown
        )
    }

    /// Where the user left the stack, given its first notice's frame.
    static func start(forFirstCard frame: NSRect, visible: NSRect) -> Start {
        let growsDown = frame.midY > visible.midY
        return Start(point: NSPoint(x: frame.minX, y: growsDown ? frame.maxY : frame.minY), growsDown: growsDown)
    }

    static func frames(count: Int, overflow: Bool, start: Start, visible: NSRect) -> Frames {
        var edge = start.point.y
        func place(_ size: NSSize) -> NSRect {
            let originY = start.growsDown ? edge - size.height : edge
            edge = start.growsDown ? originY - gap : originY + size.height + gap
            let originX = min(max(start.point.x, visible.minX), visible.maxX - size.width)
            return NSRect(x: originX, y: originY, width: size.width, height: size.height)
        }
        let cards = (0..<count).map { _ in place(NSSize(width: width, height: height)) }
        return Frames(cards: cards, overflow: overflow ? place(overflowSize) : nil)
    }
}
