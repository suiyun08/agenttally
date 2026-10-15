import AppKit

/// Aggregated session status counts used by the menubar icon, notch pill, and accessibility labels.
struct StatusCounts: Equatable {
    /// Semantic identity of a status-bar segment. Renderers resolve the
    /// theme color for a kind at render time (see `StatusColors.color(for:)`).
    enum SegmentKind: Equatable {
        case permission, attention, working, idle

        /// Whether this segment represents sessions needing user action.
        var needsAction: Bool { self == .permission || self == .attention }
    }

    let permission: Int
    let attention: Int
    let working: Int
    let idle: Int

    static let zero = StatusCounts(permission: 0, attention: 0, working: 0, idle: 0)

    /// One dot per session worth a look, grouped by agent for the menubar and notch.
    let dotGroups: [StatusDotGroup]

    init(permission: Int, attention: Int, working: Int, idle: Int, dotGroups: [StatusDotGroup] = []) {
        self.permission = permission
        self.attention = attention
        self.working = working
        self.idle = idle
        self.dotGroups = dotGroups
    }

    /// Create counts by aggregating user-session statuses.
    init(userSessions: [UserSession], now: Date = Date()) {
        var perm = 0, attn = 0, work = 0, idleCount = 0
        var dotsByFamily: [StatusDotGroup.Family: [StatusDotGroup.Dot]] = [:]
        // Only presentation-active sessions drive the menubar badge. Dormant and stale-idle
        // cards are retained for reachability, not live work, so they never inflate counts.
        for userSession in SessionDisplayPolicy.activeSessions(from: userSessions, now: now) {
            switch userSession.status {
            case .idle, .done: idleCount += 1
            case .working, .compacting, .background: work += 1
            case .waitingPermission: perm += 1
            case .waitingInput, .needsAttention: attn += 1
            }
            if let dot = StatusDotGroup.Dot(status: userSession.status) {
                let family = StatusDotGroup.Family(userSession.displayRecord.data.agentBadge)
                dotsByFamily[family, default: []].append(dot)
            }
        }
        self.dotGroups = dotsByFamily.keys.sorted().compactMap { family in
            guard let dots = dotsByFamily[family], !dots.isEmpty else { return nil }
            return StatusDotGroup(family: family, dots: dots)
        }
        self.permission = perm
        self.attention = attn
        self.working = work
        self.idle = idleCount
    }

    var total: Int { permission + attention + working + idle }
    var needsAction: Int { permission + attention }

    /// Proportional bar segments: (fraction of total, semantic kind).
    /// Used by both MenubarIconRenderer (AppKit) and NotchStatusView (SwiftUI).
    var barSegments: [(proportion: Double, kind: SegmentKind)] {
        guard total > 0 else { return [] }
        var segs: [(Double, SegmentKind)] = []
        if working > 0 {
            segs.append((Double(working) / Double(total), .working))
        }
        if attention > 0 {
            segs.append((Double(attention) / Double(total), .attention))
        }
        if permission > 0 {
            segs.append((Double(permission) / Double(total), .permission))
        }
        if idle > 0 {
            segs.append((Double(idle) / Double(total), .idle))
        }
        return segs
    }

    /// Minimum width in points for action-needing segments (permission, attention).
    private static let minActionWidth: Double = 5

    /// Bar segments with minimum width enforcement for action-needing segments.
    /// Steals space proportionally from non-action segments (working, idle).
    func barSegments(forWidth barWidth: Double) -> [(proportion: Double, kind: SegmentKind)] {
        let raw = barSegments
        guard !raw.isEmpty, barWidth > 0 else { return raw }

        let minProportion = Self.minActionWidth / barWidth

        var deficit = 0.0
        var nonActionTotal = 0.0
        var totalActionClamped = 0.0
        for seg in raw {
            if seg.kind.needsAction {
                totalActionClamped += max(seg.proportion, minProportion)
                if seg.proportion < minProportion {
                    deficit += minProportion - seg.proportion
                }
            } else {
                nonActionTotal += seg.proportion
            }
        }

        guard deficit > 0, nonActionTotal > 0 else { return raw }

        // Safety: if clamped action segments would exceed 80% of bar, skip enforcement
        guard totalActionClamped <= 0.8 else { return raw }

        var result = raw.map { seg in
            if seg.kind.needsAction && seg.proportion < minProportion {
                return (minProportion, seg.kind)
            } else if !seg.kind.needsAction {
                let shrink = deficit * (seg.proportion / nonActionTotal)
                return (max(seg.proportion - shrink, 0), seg.kind)
            }
            return seg
        }

        // Normalize to exactly 1.0 to prevent floating-point accumulation drift
        let sum = result.map { $0.0 }.reduce(0, +)
        if sum > 0 && abs(sum - 1.0) > 1e-10 {
            result = result.map { ($0.0 / sum, $0.1) }
        }

        return result
    }

    /// Human-readable summary for VoiceOver / accessibility labels.
    var accessibilityLabel: String {
        guard total > 0 else { return String(localized: "AgentTally, no sessions") }
        var parts: [String] = []
        if permission > 0 {
            parts.append(
                permission == 1 ? String(localized: "1 needs permission") : String(localized: "\(permission) need permission")
            )
        }
        if attention > 0 {
            parts.append(
                attention == 1 ? String(localized: "1 needs attention") : String(localized: "\(attention) need attention")
            )
        }
        if working > 0 { parts.append(String(localized: "\(working) working")) }
        if idle > 0 { parts.append(String(localized: "\(idle) idle")) }
        let summary = parts.joined(separator: ", ")
        return String(localized: "AgentTally, \(summary)")
    }
}

// MARK: - Menubar dots

/// The sessions of one agent family as dots: what needs the user first, then running work,
/// then unread results. Read results and idle sessions get no dot.
struct StatusDotGroup: Equatable {
    /// One agent's group: known agents in a fixed order, then any other agent by name.
    /// Claude Code and Claude Desktop share Claude's group and mark.
    struct Family: Hashable, Comparable {
        /// The badge whose mark heads the group.
        let badge: AgentBadge

        init(_ badge: AgentBadge) {
            self.badge = badge == .claudeDesktop ? .cc : badge
        }

        static let claude = Family(.cc)
        static let codex = Family(.codex)

        private var rank: Int {
            switch badge {
            case .cc, .claudeDesktop: return 0
            case .codex: return 1
            case .dsh: return 2
            case .opencode: return 3
            case .pi: return 4
            case .other: return 5
            }
        }

        static func < (lhs: Family, rhs: Family) -> Bool {
            (lhs.rank, lhs.badge.label) < (rhs.rank, rhs.badge.label)
        }
    }

    enum Dot: Int, Equatable, Comparable {
        case permission, attention, working, unreadDone

        /// `done` reaches the dots only when unread: the active list holds no read results.
        init?(status: SessionStatus) {
            switch status {
            case .waitingPermission: self = .permission
            case .waitingInput, .needsAttention: self = .attention
            case .working, .compacting, .background: self = .working
            case .done: self = .unreadDone
            case .idle: return nil
            }
        }

        static func < (lhs: Dot, rhs: Dot) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    static let defaultMaxVisibleDots = 6

    let family: Family
    /// All dots, most urgent first.
    let dots: [Dot]

    init(family: Family, dots: [Dot]) {
        self.family = family
        self.dots = dots.sorted()
    }
}

/// Sizes shared by the menubar image (AppKit) and the notch pill (SwiftUI).
struct StatusDotMetrics {
    let dotDiameter: CGFloat
    let dotGap: CGFloat
    /// Height of the agent mark heading each group.
    let markHeight: CGFloat
    /// Between a group's mark and its first dot.
    let markGap: CGFloat
    /// Between one group's last dot and the next group's mark.
    let groupGap: CGFloat
    let overflowGap: CGFloat
    let overflowFont: NSFont

    static let menubar = StatusDotMetrics(
        dotDiameter: 6, dotGap: 3, markHeight: 10, markGap: 3, groupGap: 6, overflowGap: 2,
        overflowFont: .monospacedDigitSystemFont(ofSize: 9, weight: .medium)
    )
    static let notch = StatusDotMetrics(
        dotDiameter: 5, dotGap: 3, markHeight: 8, markGap: 3, groupGap: 5, overflowGap: 2,
        overflowFont: .monospacedDigitSystemFont(ofSize: 8, weight: .medium)
    )
}

/// Horizontal positions of every agent mark, dot, and "+N" label, plus the total width.
struct StatusDotLayout: Equatable {
    enum Item: Equatable {
        case mark(AgentBadge, xPos: CGFloat, width: CGFloat)
        case dot(StatusDotGroup.Dot, xPos: CGFloat)
        case overflow(String, xPos: CGFloat, width: CGFloat)
    }

    let items: [Item]
    let width: CGFloat

    /// With `maxWidth`, each group shows fewer dots (the rest move into "+N") until it fits.
    init(groups: [StatusDotGroup], metrics: StatusDotMetrics, maxWidth: CGFloat? = nil) {
        var cap = StatusDotGroup.defaultMaxVisibleDots
        var layout = Self.layout(groups: groups, metrics: metrics, maxVisibleDots: cap)
        if let maxWidth {
            while layout.width > maxWidth, cap > 1 {
                cap -= 1
                layout = Self.layout(groups: groups, metrics: metrics, maxVisibleDots: cap)
            }
        }
        items = layout.items
        width = layout.width
    }

    private static func layout(
        groups: [StatusDotGroup], metrics: StatusDotMetrics, maxVisibleDots: Int
    ) -> (items: [Item], width: CGFloat) {
        var items: [Item] = []
        var xPos: CGFloat = 0
        for (index, group) in groups.enumerated() {
            if index > 0 { xPos += metrics.groupGap }
            let markWidth = AgentMark.width(for: group.family.badge, height: metrics.markHeight)
            items.append(.mark(group.family.badge, xPos: xPos, width: markWidth))
            xPos += markWidth + metrics.markGap
            let visible = group.dots.prefix(maxVisibleDots)
            for (dotIndex, dot) in visible.enumerated() {
                if dotIndex > 0 { xPos += metrics.dotGap }
                items.append(.dot(dot, xPos: xPos))
                xPos += metrics.dotDiameter
            }
            let hidden = group.dots.count - visible.count
            if hidden > 0 {
                let text = "+\(hidden)"
                let textWidth = ceil(NSAttributedString(
                    string: text, attributes: [.font: metrics.overflowFont]
                ).size().width)
                xPos += metrics.overflowGap
                items.append(.overflow(text, xPos: xPos, width: textWidth))
                xPos += textWidth
            }
        }
        return (items, xPos)
    }
}
