import Foundation

struct WorktreeCleanupCandidate: Identifiable, Equatable {
    static let untrackedFilesReason = "Worktree has untracked files"
    static let ignoredFilesReason = "Worktree has ignored files"
    static let trackedChangesReason = "Worktree has uncommitted tracked changes"
    static let lockedReason = "Worktree is locked"
    static let initializedSubmodulesReason = "Worktree contains initialized submodules"
    static let indexHiddenTrackedFilesReason = "Worktree has tracked files hidden by Git index flags"
    static let statusUnreadableReason = "Git status could not be read"
    static let branchUnknownReason = "Branch safety cannot be verified because the branch is unknown or detached"
    static let unknownBranchDisplayName = "unknown / detached"
    static let mainWorktreePathUnverifiedReason = "Main checkout path could not be verified"
    static let commitSafetyUnknownReason = "Branch upstream or commit safety could not be verified"
    static let protectedFolderAccessReason = "File access is needed to inspect this protected worktree"
    private static let localFileReasons = [untrackedFilesReason, ignoredFilesReason]

    enum State: Equatable {
        case clean
        case review([String])
        case ignored([String])

        var label: String {
            switch self {
            case .clean: return String(localized: "Clean")
            case .review: return String(localized: "Review")
            case .ignored: return String(localized: "Ignored")
            }
        }

        var reasons: [String] {
            switch self {
            case .clean: return []
            case .review(let reasons), .ignored(let reasons): return reasons
            }
        }

        var isClean: Bool {
            if case .clean = self { return true }
            return false
        }

        var isActionable: Bool {
            switch self {
            case .clean, .review:
                return true
            case .ignored:
                return false
            }
        }
    }

    let id: String
    let sessionName: String
    let worktreePath: String
    let worktreeName: String
    let mainWorktreePath: String?
    let branchName: String
    let lastActiveAt: Date
    let storageBytes: Int64?
    let state: State
    let checks: [WorktreeCleanupCheck]
    let reviewEvidence: WorktreeCleanupReviewEvidence

    init(
        id: String,
        sessionName: String,
        worktreePath: String,
        worktreeName: String,
        mainWorktreePath: String? = nil,
        branchName: String,
        lastActiveAt: Date,
        storageBytes: Int64?,
        state: State,
        checks: [WorktreeCleanupCheck],
        reviewEvidence: WorktreeCleanupReviewEvidence = .empty
    ) {
        self.id = id
        self.sessionName = sessionName
        self.worktreePath = worktreePath
        self.worktreeName = worktreeName
        self.mainWorktreePath = mainWorktreePath
        self.branchName = branchName
        self.lastActiveAt = lastActiveAt
        self.storageBytes = storageBytes
        self.state = state
        self.checks = checks
        self.reviewEvidence = reviewEvidence
    }

    var formattedStorage: String {
        Self.formatStorage(bytes: storageBytes)
    }

    var requiresForceRemovalReview: Bool {
        requiresGitForceRemoval || state.reasons.contains(Self.branchUnknownReason)
    }

    var requiresGitForceRemoval: Bool {
        state.reasons.contains(Self.untrackedFilesReason)
            || state.reasons.contains(Self.trackedChangesReason)
    }

    func visibleReviewReasons(limit: Int = 3) -> [String] {
        let reasons = state.reasons
        guard limit > 0 else { return [] }
        let cappedReasons = Array(reasons.prefix(limit))
        guard let localFileReason = Self.localFileReasons.first(where: { reason in
            guard let index = reasons.firstIndex(of: reason) else { return false }
            return index >= limit && !cappedReasons.contains(reason)
        }) else {
            return cappedReasons
        }
        if limit == 1 {
            return [localFileReason]
        }
        return Array(reasons.prefix(limit - 1)) + [localFileReason]
    }

    func remainingReviewReasonCount(limit: Int = 3) -> Int {
        max(state.reasons.count - visibleReviewReasons(limit: limit).count, 0)
    }

    /// Reasons stay English inside cleanup logic (they are compared and matched); translate them
    /// only where they are shown.
    static func displayReason(_ reason: String) -> String {
        knownReasonTranslations[reason] ?? uniqueCommitDisplayReason(reason) ?? reason
    }

    private static var knownReasonTranslations: [String: String] {
        [
            untrackedFilesReason: String(localized: "Worktree has untracked files"),
            ignoredFilesReason: String(localized: "Worktree has ignored files"),
            trackedChangesReason: String(localized: "Worktree has uncommitted tracked changes"),
            lockedReason: String(localized: "Worktree is locked"),
            initializedSubmodulesReason: String(localized: "Worktree contains initialized submodules"),
            indexHiddenTrackedFilesReason: String(localized: "Worktree has tracked files hidden by Git index flags"),
            statusUnreadableReason: String(localized: "Git status could not be read"),
            branchUnknownReason: String(localized: "Branch safety cannot be verified because the branch is unknown or detached"),
            mainWorktreePathUnverifiedReason: String(localized: "Main checkout path could not be verified"),
            commitSafetyUnknownReason: String(localized: "Branch upstream or commit safety could not be verified"),
            protectedFolderAccessReason: String(localized: "File access is needed to inspect this protected worktree"),
            "Path is not a registered Git worktree": String(localized: "Path is not a registered Git worktree"),
            "Path is not listed by Git worktree metadata": String(localized: "Path is not listed by Git worktree metadata"),
            "No upstream branch": String(localized: "No upstream branch"),
            "Branch unique commits could not be verified": String(localized: "Branch unique commits could not be verified"),
        ]
    }

    private static func uniqueCommitDisplayReason(_ reason: String) -> String? {
        guard let match = reason.range(of: #"^Branch has (\d+) unique local commits?$"#, options: .regularExpression),
              match == reason.startIndex..<reason.endIndex,
              let count = Int(reason.dropFirst("Branch has ".count).prefix { $0.isNumber }) else { return nil }
        return count == 1
            ? String(localized: "Branch has 1 unique local commit")
            : String(localized: "Branch has \(count) unique local commits")
    }

    static var unknownBranchDisplayText: String {
        String(localized: "unknown / detached")
    }

    /// `branchName` stores the English sentinel for unknown branches; show it translated.
    var displayBranchName: String {
        branchName == Self.unknownBranchDisplayName ? Self.unknownBranchDisplayText : branchName
    }

    static func formatStorage(bytes: Int64?) -> String {
        guard let bytes else { return String(localized: "Unknown") }
        if bytes < 1_024 { return "\(bytes) B" }
        let kilobytes = Double(bytes) / 1_024.0
        if kilobytes < 1_024 { return "\(Int(kilobytes.rounded())) KB" }
        let megabytes = kilobytes / 1_024.0
        if megabytes < 1_024 { return "\(Int(megabytes.rounded())) MB" }
        let gigabytes = megabytes / 1_024.0
        let rounded = (gigabytes * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return "\(Int(rounded)) GB"
        }
        return String(format: "%.1f GB", rounded)
    }
}

struct WorktreeCleanupReviewEvidence: Equatable {
    static let empty = WorktreeCleanupReviewEvidence()

    let untrackedPreview: WorktreeCleanupUntrackedPreview?
    let ignoredPreview: WorktreeCleanupUntrackedPreview?
    let trackedPathSignature: [String]
    let headRevision: String?

    init(
        untrackedPreview: WorktreeCleanupUntrackedPreview? = nil,
        ignoredPreview: WorktreeCleanupUntrackedPreview? = nil,
        trackedPathSignature: [String] = [],
        headRevision: String? = nil
    ) {
        self.untrackedPreview = untrackedPreview
        self.ignoredPreview = ignoredPreview
        self.trackedPathSignature = trackedPathSignature
        self.headRevision = headRevision
    }

    var hasLocalFilePreview: Bool {
        untrackedPreview != nil || ignoredPreview != nil
    }
}

struct WorktreeCleanupUntrackedPreview: Equatable {
    let items: [String]
    let totalCount: Int
    private let sourcePathSignature: [String]

    var remainingCount: Int {
        max(totalCount - items.count, 0)
    }

    var decisionEvidenceText: String {
        var evidenceItems = items
        if remainingCount > 0 {
            evidenceItems.append(String(localized: "and \(remainingCount) more"))
        }
        return evidenceItems.joined(separator: ", ")
    }

    init?(paths: [String], visibleLimit: Int = 3) {
        let sourcePaths = paths
            .filter { !$0.isEmpty }
        let displayItems = Self.displayItems(from: sourcePaths)
        guard !displayItems.isEmpty else { return nil }
        self.items = Array(displayItems.prefix(visibleLimit))
        totalCount = sourcePaths.count
        sourcePathSignature = Array(Set(sourcePaths)).sorted()
    }

    private static func displayItems(from paths: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for path in paths where !path.isEmpty {
            let item = displayItem(for: path)
            if seen.insert(item).inserted {
                result.append(item)
            }
        }
        return result
    }

    private static func displayItem(for path: String) -> String {
        if path.hasSuffix("/") {
            return path
        }
        guard let slash = path.firstIndex(of: "/") else {
            return path
        }
        let firstComponent = path[..<slash]
        guard !firstComponent.isEmpty else {
            return path
        }
        return "\(firstComponent)/"
    }
}

struct WorktreeCleanupCheck: Equatable {
    enum Status: Equatable {
        case ok
        case review
        case ignored

        var label: String {
            switch self {
            case .ok: return "OK"
            case .review: return "Review"
            case .ignored: return "Ignored"
            }
        }
    }

    let label: String
    let status: Status
}

enum WorktreeRemovalConfirmation: Identifiable, Equatable {
    case review(WorktreeRemovalService.RemovalAction)

    private static var branchRetentionCopy: String {
        String(localized: "Removing the worktree does not delete the branch.")
    }

    var id: String {
        switch self {
        case .review(let action):
            return "review-\(action.candidate.id)-\(action.isForce ? "force" : "normal")"
        }
    }

    var candidate: WorktreeCleanupCandidate {
        switch self {
        case .review(let action):
            return action.candidate
        }
    }

    var title: String {
        switch self {
        case .review(let action):
            return action.isForce ? String(localized: "Force Remove Worktree?") : String(localized: "Remove Review Worktree?")
        }
    }

    var message: String {
        switch self {
        case .review(.normalRemove(let candidate)):
            return String(localized: "Runs git worktree remove for \(candidate.worktreeName).") + " "
                + "\(Self.reviewEvidenceCopy(for: candidate)) \(Self.branchRetentionCopy)"
        case .review(.forceRemove(let candidate)):
            let command = candidate.requiresGitForceRemoval ? "git worktree remove --force" : "git worktree remove"
            let fileRiskCopy = candidate.requiresGitForceRemoval
                ? String(localized: "This removes local file changes and files in that worktree.")
                : ""
            let lateChangeGuard = candidate.requiresGitForceRemoval
                ? ""
                : String(
                    localized: "Git will refuse removal if tracked changes or non-ignored untracked files appeared after this review."
                )
            let branchRetention = candidate.state.reasons.contains(WorktreeCleanupCandidate.branchUnknownReason)
                ? ""
                : Self.branchRetentionCopy
            return [
                String(localized: "Runs \(command) for \(candidate.worktreeName)."),
                Self.reviewEvidenceCopy(for: candidate),
                fileRiskCopy,
                lateChangeGuard,
                branchRetention,
            ].filter { !$0.isEmpty }.joined(separator: " ")
        case .review(.blocked(_, let reason)):
            return reason
        }
    }

    var primaryButtonTitle: String {
        switch self {
        case .review(let action):
            return action.isForce ? String(localized: "Force Remove") : String(localized: "Remove")
        }
    }

    static func review(for action: WorktreeRemovalService.RemovalAction) -> WorktreeRemovalConfirmation? {
        switch action {
        case .normalRemove(let candidate) where candidate.state.isClean:
            return nil
        case .normalRemove, .forceRemove:
            return .review(action)
        case .blocked:
            return nil
        }
    }

    private static func reviewEvidenceCopy(for candidate: WorktreeCleanupCandidate) -> String {
        var parts: [String] = []
        let reasons = candidate.visibleReviewReasons().map(WorktreeCleanupCandidate.displayReason)
        if !reasons.isEmpty {
            let joinedReasons = reasons.joined(separator: "; ")
            var reasonCopy = String(localized: "Reasons: \(joinedReasons)")
            let remainingCount = candidate.remainingReviewReasonCount()
            if remainingCount > 0 {
                reasonCopy += String(localized: "; and \(remainingCount) more")
            }
            parts.append(reasonCopy + ".")
        }

        if let preview = candidate.reviewEvidence.untrackedPreview {
            let files = preview.decisionEvidenceText
            parts.append(String(localized: "Untracked files: \(files)."))
        }
        if let preview = candidate.reviewEvidence.ignoredPreview {
            let files = preview.decisionEvidenceText
            parts.append(String(localized: "Ignored files: \(files)."))
            parts.append(String(localized: "Ignored files will be removed with this worktree."))
        }

        return parts.joined(separator: " ")
    }
}

extension WorktreeRemovalService.RemovalAction {
    var candidate: WorktreeCleanupCandidate {
        switch self {
        case .normalRemove(let candidate), .forceRemove(let candidate), .blocked(let candidate, _):
            return candidate
        }
    }

    var isForce: Bool {
        if case .forceRemove = self { return true }
        return false
    }
}
