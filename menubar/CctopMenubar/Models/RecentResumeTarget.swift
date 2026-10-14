import Foundation

enum RecentResumeTarget: Identifiable, Equatable {
    struct DesktopThread: Equatable {
        let sessionId: String
        let cctopSessionId: String?
        let title: String
        let projectPath: String
        let projectName: String
        let lastActiveAt: Date

        init(
            sessionId: String,
            cctopSessionId: String? = nil,
            title: String,
            projectPath: String,
            projectName: String,
            lastActiveAt: Date
        ) {
            self.sessionId = sessionId
            self.cctopSessionId = cctopSessionId
            self.title = title
            self.projectPath = projectPath
            self.projectName = projectName
            self.lastActiveAt = lastActiveAt
        }
    }

    case project(RecentProject)
    case desktopThread(DesktopThread)
    /// A disconnected (dormant) session whose host can still reopen it.
    case session(SessionData)

    /// Recent covers the last 7 days.
    static let window: TimeInterval = 7 * 86_400

    var id: String {
        switch self {
        case .project(let project):
            return "project:\(project.id)"
        case .desktopThread(let thread):
            if let cctopSessionID = thread.cctopSessionId,
               CctopSessionID.isValid(cctopSessionID) {
                return "desktop:\(cctopSessionID)"
            }
            return "desktop:Claude Desktop:\(thread.sessionId)"
        case .session(let session):
            return "session:\(session.cctopSessionId ?? session.id)"
        }
    }

    var title: String {
        switch self {
        case .project(let project):
            return project.projectName
        case .desktopThread(let thread):
            return thread.title
        case .session(let session):
            return session.displayName
        }
    }

    var projectPath: String {
        switch self {
        case .project(let project):
            return project.projectPath
        case .desktopThread(let thread):
            return thread.projectPath
        case .session(let session):
            return session.projectPath
        }
    }

    var cctopSessionId: String? {
        switch self {
        case .project: return nil
        case .desktopThread(let thread): return thread.cctopSessionId
        case .session(let session): return session.cctopSessionId
        }
    }

    var lastSessionAt: Date {
        switch self {
        case .project(let project):
            return project.lastSessionAt
        case .desktopThread(let thread):
            return thread.lastActiveAt
        case .session(let session):
            return session.effectiveEndDate
        }
    }

    var icon: String {
        switch self {
        case .project(let project):
            return project.editorIcon
        case .desktopThread:
            return HostApp.claudeDesktop.sfSymbol
        case .session(let session):
            return (session.trustedHostApp ?? (session.isCodex ? .codexDesktop : .unknown)).sfSymbol
        }
    }

    var opensProjectInApp: Bool {
        switch self {
        case .project(let project):
            return project.opensWithProjectApp
        case .desktopThread, .session:
            return false
        }
    }

    var showsFinderAction: Bool {
        switch self {
        case .project:
            return opensProjectInApp
        case .desktopThread, .session:
            return false
        }
    }

    var showsCopyPathAction: Bool {
        switch self {
        case .project, .session:
            return true
        case .desktopThread:
            return false
        }
    }

    var openActionLabel: String {
        switch self {
        case .project(let project):
            return project.openActionLabel
        case .desktopThread:
            return String(localized: "Open Claude Desktop")
        case .session:
            return String(localized: "Open Session")
        }
    }

    var inlineActionLabel: String? {
        switch self {
        case .project, .session:
            return nil
        case .desktopThread:
            return String(localized: "Open Claude")
        }
    }

    var openHelpText: String {
        switch self {
        case .project(let project):
            return project.openHelpText
        case .desktopThread:
            return String(localized: "Open Claude Desktop; archived sessions may need manual lookup")
        case .session:
            return String(localized: "Click to reopen this session")
        }
    }

    var metadataText: String {
        switch self {
        case .project(let project):
            return Self.joinedMetadata([project.metadataEvidenceText, project.pathContext])
        case .desktopThread(let thread):
            return Self.joinedMetadata([String(localized: "Archived"), "Claude", RecentProject.compactProjectPath(thread.projectPath)])
        case .session(let session):
            return Self.joinedMetadata([
                session.agentBadge.label,
                session.desktopProjectName ?? session.projectName,
            ])
        }
    }

    static func build(
        projects: [RecentProject],
        classification: SessionClassificationSnapshot,
        dormantSessions: [SessionData] = [],
        excludingDesktopSessionIDs: Set<String> = [],
        now: Date = Date(),
        limit: Int = 30
    ) -> [RecentResumeTarget] {
        let projectTargets = projects.map(RecentResumeTarget.project)
        let desktopTargets = desktopThreadTargets(
            from: classification,
            excludingSessionIDs: excludingDesktopSessionIDs
        )
        let sessionTargets = dormantSessions.map(RecentResumeTarget.session)
        let cutoff = now.addingTimeInterval(-window)
        return Array((projectTargets + desktopTargets + sessionTargets)
            .filter { $0.lastSessionAt >= cutoff }
            .sorted { $0.lastSessionAt > $1.lastSessionAt }
            .prefix(limit))
    }

    private static func desktopThreadTargets(
        from classification: SessionClassificationSnapshot,
        excludingSessionIDs: Set<String>
    ) -> [RecentResumeTarget] {
        var targetsByID: [String: (target: RecentResumeTarget, candidate: SessionRecord)] = [:]
        for record in classification.records {
            if let cctopSessionID = record.candidate.data.cctopSessionId,
               excludingSessionIDs.contains(cctopSessionID) {
                continue
            }
            guard isArchivedClaudeDesktop(record.disposition),
                  let thread = DesktopThread(session: record.candidate.data) else {
                continue
            }
            let target = RecentResumeTarget.desktopThread(thread)
            if let existing = targetsByID[target.id],
               !SessionLifecyclePolicy.prefers(record.candidate, over: existing.candidate) {
                continue
            }
            targetsByID[target.id] = (target, record.candidate)
        }
        return targetsByID.values.map(\.target)
    }

    private static func isArchivedClaudeDesktop(_ disposition: SessionDisposition) -> Bool {
        guard case .hidden(.archivedClaudeDesktop) = disposition else { return false }
        return true
    }

    private static func joinedMetadata(_ parts: [String]) -> String {
        parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " \u{00B7} ")
    }
}

extension RecentResumeTarget.DesktopThread {
    init?(session: SessionData) {
        let title = Self.displayTitle(for: session)
        guard !title.isEmpty else { return nil }
        self.init(
            sessionId: session.sessionId,
            cctopSessionId: session.cctopSessionId,
            title: title,
            projectPath: session.projectPath,
            projectName: session.desktopProjectName ?? session.projectName,
            lastActiveAt: session.effectiveEndDate
        )
    }

    private static func displayTitle(for session: SessionData) -> String {
        [
            session.sessionName,
            session.lastPrompt,
            session.desktopProjectName,
            session.projectName,
        ]
        .compactMap { value -> String? in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
        .first ?? ""
    }
}
