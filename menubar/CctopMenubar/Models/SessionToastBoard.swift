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

    /// The notices that show, at most `limit`. Given `held`, the order showing while the pointer
    /// rests on them, those still showing keep their places and newcomers go after them, so
    /// nothing moves under the pointer.
    func visible(limit: Int, holding held: [String] = []) -> [SessionToast] {
        guard !held.isEmpty else { return Array(toasts.prefix(limit)) }
        let kept = held.compactMap { id in toasts.first { $0.id == id } }
        let newcomers = toasts.filter { !held.contains($0.id) }
        return Array((kept + newcomers).prefix(limit))
    }

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
        // Ties go by session ID, so equal times never swap places between refreshes.
        toasts = candidates
            .filter { !closed.contains($0.id) }
            .sorted { $0.lastActivity != $1.lastActivity ? $0.lastActivity > $1.lastActivity : $0.id < $1.id }
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
    static let cornerRadius: CGFloat = 14
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

    /// How many of `total` notices show from `start`: at most `limit`, and only as many as fit
    /// on screen, leaving room for the "N more" when some must wait behind it.
    static func shownCount(limit: Int, of total: Int, start: Start, visible: NSRect) -> Int {
        let room = start.growsDown ? start.point.y - visible.minY : visible.maxY - start.point.y
        let step = height + gap
        let wanted = min(limit, total)
        if wanted == total, CGFloat(wanted) * step - gap <= room { return wanted }
        let fitting = Int(((room - overflowSize.height) / step).rounded(.down))
        return max(1, min(wanted, fitting))
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
