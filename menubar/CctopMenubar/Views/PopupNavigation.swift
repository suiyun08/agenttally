import Foundation

enum PopupTab: CaseIterable, Hashable {
    case active, idle, recent, cleanup

    var label: String {
        switch self {
        case .active: return String(localized: "Active")
        // Own key: the tab ("idle sessions") and the card status ("idle") translate differently.
        case .idle: return String(localized: "tab.idle", defaultValue: "Idle")
        case .recent: return String(localized: "Recent")
        case .cleanup: return String(localized: "Cleanup")
        }
    }

    var helpText: String {
        switch self {
        case .active:
            return String(localized: "Sessions that are working or waiting for you, including unread results.")
        case .idle:
            return String(localized: "Open sessions with nothing to do: read results and sessions not started yet.")
        case .recent:
            return String(localized: "Disconnected sessions from the last 7 days. Rows reopen the session or project when possible.")
        case .cleanup:
            return String(localized: "Ended-session worktrees checked before removal.")
        }
    }

    var emptyStateDetail: String {
        switch self {
        case .active:
            return String(localized: "Working sessions and unread results appear here.")
        case .idle:
            return String(localized: "Read results and sessions not started yet appear here.")
        case .recent:
            return String(localized: "Disconnected sessions from the last 7 days appear here.")
        case .cleanup:
            return String(localized: "Ended-session worktrees appear here after checks.")
        }
    }

    static var cleanupScanningDetail: String {
        String(localized: "Checking ended-session worktrees.")
    }

    static func switched(
        from current: PopupTab,
        action: PanelNavAction,
        availableTabs: [PopupTab]
    ) -> PopupTab {
        guard let currentIndex = availableTabs.firstIndex(of: current), !availableTabs.isEmpty else {
            return .active
        }
        switch action {
        case .previousTab:
            return availableTabs[(currentIndex - 1 + availableTabs.count) % availableTabs.count]
        case .nextTab, .toggleTab:
            return availableTabs[(currentIndex + 1) % availableTabs.count]
        default:
            return current
        }
    }
}

struct PopupSelectionContext {
    let recentTargets: [RecentResumeTarget]
    let cleanupCandidates: [WorktreeCleanupCandidate]

    init(
        recentProjects: [RecentProject] = [],
        recentResumeTargets: [RecentResumeTarget]? = nil,
        cleanupCandidates: [WorktreeCleanupCandidate]
    ) {
        self.recentTargets = recentResumeTargets ?? recentProjects.map(RecentResumeTarget.project)
        self.cleanupCandidates = cleanupCandidates
    }
}

enum PopupSelectionTarget: Equatable {
    case recentTarget(RecentResumeTarget)
    case cleanupCandidate(WorktreeCleanupCandidate)

    var confirmsNavigate: Bool {
        switch self {
        case .recentTarget:
            return true
        case .cleanupCandidate:
            return false
        }
    }

    static func target(
        for tab: PopupTab,
        index: Int,
        in context: PopupSelectionContext
    ) -> PopupSelectionTarget? {
        switch tab {
        case .active, .idle:
            return nil
        case .recent:
            guard index < context.recentTargets.count else { return nil }
            return .recentTarget(context.recentTargets[index])
        case .cleanup:
            guard index < context.cleanupCandidates.count else { return nil }
            return .cleanupCandidate(context.cleanupCandidates[index])
        }
    }
}
