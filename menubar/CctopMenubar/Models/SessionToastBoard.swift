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

    /// Waiting for the user's permission or answer; a session stopped by an error is not.
    var waitsForUser: Bool { status == .waitingPermission || status == .waitingInput }
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
    /// rests on them, those still showing keep their places and newcomers wait behind the count,
    /// so nothing moves under the pointer, the count included.
    func visible(limit: Int, holding held: [String] = []) -> [SessionToast] {
        guard !held.isEmpty else { return Array(toasts.prefix(limit)) }
        let kept = held.compactMap { id in toasts.first { $0.id == id } }
        return Array(kept.prefix(limit))
    }

    /// How many notices wait behind the count while `shown` show.
    func waitingCount(besides shown: [SessionToast]) -> Int { toasts.count - shown.count }

    /// Brings the notices in line with the sessions that are working or need the user now.
    /// Returns whether a session newly needs the user or newly finished, with a notice showing
    /// for it: a reason to show the notices for a moment. Never on the board's first update.
    @discardableResult
    mutating func update(_ candidates: [SessionToast]) -> Bool {
        var kinds: [String: SessionToast.Kind] = [:]
        var alerting: Set<String> = []
        for candidate in candidates {
            kinds[candidate.id] = candidate.kind
            let before = lastKinds[candidate.id]
            if started, candidate.kind != .working, before != candidate.kind { alerting.insert(candidate.id) }
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
        return toasts.contains { alerting.contains($0.id) }
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

/// When the floating notices show, as the panel shows for the menu bar dots: while the pointer
/// rests on the floating indicator or on the notices, while pinned by a click on the indicator,
/// while a session waits for the user's permission or answer, and for a few seconds when a
/// session finishes. A click while they show for good puts them away, waiting sessions included
/// until another starts waiting; resting the pointer brings them back only after it has left once.
struct SessionToastVisibility: Equatable {
    static let alertDuration: TimeInterval = 5

    private(set) var pinned = false
    private(set) var peeking = false
    private(set) var alertUntil: Date?
    /// Sessions waiting for the user's permission or answer, and those a click put away.
    private(set) var waiting: Set<String> = []
    private var dismissedWaiting: Set<String> = []
    /// Set by a click that put the notices away while the pointer was still on the indicator.
    private var peekWaitsForLeave = false

    /// A session waits for the user that no click has put away.
    var showsForWaiting: Bool { !waiting.subtracting(dismissedWaiting).isEmpty }

    func isVisible(now: Date) -> Bool {
        pinned || peeking || showsForWaiting || (alertUntil.map { now < $0 } ?? false)
    }

    /// A click on the floating indicator: pins the notices, or puts away notices that show for
    /// good, pinned or held out by waiting sessions.
    mutating func toggle() {
        if pinned || showsForWaiting {
            pinned = false
            peeking = false
            alertUntil = nil
            dismissedWaiting = waiting
            peekWaitsForLeave = true
        } else {
            pinned = true
        }
    }

    /// The sessions waiting for the user now; one that starts waiting again shows them again.
    mutating func setWaiting(_ ids: Set<String>) {
        waiting = ids
        dismissedWaiting.formIntersection(ids)
    }

    mutating func setPeeking(_ on: Bool) {
        if on {
            peeking = !peekWaitsForLeave
        } else {
            peeking = false
            peekWaitsForLeave = false
        }
    }

    /// The pointer left the floating indicator: resting on it again may show the notices.
    mutating func pointerLeftIndicator() {
        peekWaitsForLeave = false
    }

    mutating func alert(now: Date) {
        alertUntil = now.addingTimeInterval(Self.alertDuration)
    }
}

/// Where the floating notices sit: a stack lined up with its left edge, growing down from its top
/// when it starts in the upper half of the screen and up from its bottom in the lower half. It
/// always starts under (or over) the floating indicator, lined up with it.
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

    /// How far the stack can run from its start before it leaves the screen.
    static func room(from start: Start, visible: NSRect) -> CGFloat {
        start.growsDown ? start.point.y - visible.minY : visible.maxY - start.point.y
    }

    /// How far the stack runs from its start.
    static func length(of frames: Frames, start: Start) -> CGFloat {
        let all = frames.cards + [frames.overflow].compactMap { $0 }
        guard let far = start.growsDown ? all.map(\.minY).min() : all.map(\.maxY).max() else { return 0 }
        return abs(start.point.y - far)
    }

    /// The frames moved back toward the start by `offset`, as when scrolled that far.
    static func scrolled(_ frames: Frames, by offset: CGFloat, growsDown: Bool) -> Frames {
        let shift = growsDown ? offset : -offset
        return Frames(
            cards: frames.cards.map { $0.offsetBy(dx: 0, dy: shift) },
            overflow: frames.overflow.map { $0.offsetBy(dx: 0, dy: shift) }
        )
    }

    /// The part of the screen a scrolled stack shows: from its start to the screen's edge.
    static func viewport(start: Start, visible: NSRect, minX: CGFloat) -> NSRect {
        let room = room(from: start, visible: visible)
        let originY = start.growsDown ? start.point.y - room : start.point.y
        return NSRect(x: minX, y: originY, width: width, height: room)
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
