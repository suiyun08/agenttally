import AppKit

/// What the agent clients themselves know about reading, sampled once per load pass so a
/// finished turn the user already read in Claude Desktop or Codex Desktop loses its unread dot.
struct ClientReadSnapshot: Equatable {
    /// Codex Desktop's unread thread IDs and when it last wrote them. Nil when the state file is
    /// missing or unreadable, which leaves Codex unread dots to cctop's own rule.
    var codexUnread: CodexUnread?
    /// Claude Desktop's last focus time for each Claude Code `session_id` (current and prior).
    var claudeFocusByCliSessionID: [String: Date] = [:]
    /// Claude Code `session_id`s of the conversation focused most recently in Claude Desktop.
    var claudeCurrentCliSessionIDs: Set<String> = []
    var claudeIsFrontmost = false

    struct CodexUnread: Equatable {
        let threadIDs: Set<String>
        let writtenAt: Date
    }

    static let empty = ClientReadSnapshot()
}

protocol ClientReadStateProviding {
    func snapshot() -> ClientReadSnapshot
}

/// Tests and previews: no client knows anything.
struct NoClientReadState: ClientReadStateProviding {
    func snapshot() -> ClientReadSnapshot { .empty }
}

/// When a client's own state says the user has seen a finished turn. Anything uncertain answers
/// false, so a dot is never cleared by a guess.
enum ClientReadPolicy {
    static func seenInClient(_ session: SessionData, snapshot: ClientReadSnapshot) -> Bool {
        guard session.status == .done else { return false }
        let finishedAt = session.statusChangedAt ?? session.lastActivity
        let clientSessionID = session.harnessSessionId ?? session.sessionId

        if session.isCodex {
            // Codex Desktop marks a thread unread when a turn finishes off screen. Trust its
            // silence only once it has written its state after this turn finished.
            guard session.isCodexDesktopThread,
                  let codex = snapshot.codexUnread,
                  codex.writtenAt > finishedAt else { return false }
            return !codex.threadIDs.contains(clientSessionID)
        }

        guard session.isClaudeDesktopHost else { return false }
        if let focusedAt = snapshot.claudeFocusByCliSessionID[clientSessionID], focusedAt >= finishedAt {
            return true
        }
        // Claude is in front and showing this conversation.
        return snapshot.claudeIsFrontmost && snapshot.claudeCurrentCliSessionIDs.contains(clientSessionID)
    }
}

extension SessionData {
    /// Codex Desktop threads carry no terminal metadata; CLI sessions record their terminal. A
    /// Feishu bridge's `codex exec` has no terminal either, but Codex Desktop never lists it.
    var isCodexDesktopThread: Bool {
        guard isCodex, larkChannelProfile == nil else { return false }
        let program = terminal?.program.trimmingCharacters(in: .whitespaces) ?? ""
        let tty = terminal?.tty?.trimmingCharacters(in: .whitespaces) ?? ""
        return program.isEmpty && tty.isEmpty
    }
}

/// Reads Codex Desktop's global state and Claude Desktop's session metadata from disk.
/// Both are re-parsed only when their files change.
final class ClientReadStateLookup: ClientReadStateProviding {
    private let codexStatePath: String
    private let claudeSessionsDirectory: String
    private let frontmostBundleID: () -> String?
    /// Whether Claude Desktop was in front around a moment, so its focus stamp means a look.
    private let claudeWasFrontmost: (Date) -> Bool

    private var codexCache: (signature: FileSignature, unread: ClientReadSnapshot.CodexUnread?)?
    private var claudeCache: (signature: [FileSignature], records: [ClaudeDesktopSessionLinkMetadata])?

    init(
        codexStatePath: String = Config.codexGlobalStatePath(),
        claudeSessionsDirectory: String = Config.claudeCodeSessionsDir(),
        frontmostBundleID: @escaping () -> String? = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        },
        claudeWasFrontmost: ((Date) -> Bool)? = nil
    ) {
        self.codexStatePath = codexStatePath
        self.claudeSessionsDirectory = claudeSessionsDirectory
        self.frontmostBundleID = frontmostBundleID
        if let claudeWasFrontmost {
            self.claudeWasFrontmost = claudeWasFrontmost
        } else {
            let history = FrontmostAppHistory(frontmost: frontmostBundleID())
            self.claudeWasFrontmost = { history.wasFrontmost(HostAppBundleID.claudeDesktop, around: $0) }
        }
    }

    func snapshot() -> ClientReadSnapshot {
        let focus = claudeFocus()
        return ClientReadSnapshot(
            codexUnread: codexUnread(),
            claudeFocusByCliSessionID: focus.byCliSessionID,
            claudeCurrentCliSessionIDs: focus.current,
            claudeIsFrontmost: frontmostBundleID() == HostAppBundleID.claudeDesktop
        )
    }

    // MARK: - Codex Desktop

    private func codexUnread() -> ClientReadSnapshot.CodexUnread? {
        guard let signature = FileSignature(path: codexStatePath) else { return nil }
        if let codexCache, codexCache.signature == signature { return codexCache.unread }
        let unread = FileManager.default.contents(atPath: codexStatePath)
            .flatMap { Self.parseCodexUnreadThreadIDs($0) }
            .map { ClientReadSnapshot.CodexUnread(threadIDs: $0, writtenAt: signature.modified) }
        codexCache = (signature, unread)
        return unread
    }

    /// `electron-thread-read-state-v1.unreadByIdentity` maps account → host → unread thread IDs.
    static func parseCodexUnreadThreadIDs(_ data: Data) -> Set<String>? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let readState = root["electron-thread-read-state-v1"] as? [String: Any],
              let byIdentity = readState["unreadByIdentity"] as? [String: Any] else { return nil }
        var threadIDs: Set<String> = []
        for case let byHost as [String: Any] in byIdentity.values {
            for case let ids as [String] in byHost.values {
                threadIDs.formUnion(ids)
            }
        }
        return threadIDs
    }

    // MARK: - Claude Desktop

    struct ClaudeFocus: Equatable {
        var byCliSessionID: [String: Date] = [:]
        var current: Set<String> = []
    }

    private func claudeFocus() -> ClaudeFocus {
        let urls = Self.metadataURLs(in: claudeSessionsDirectory)
        let signature = urls.compactMap { FileSignature(path: $0.path) }
        let records: [ClaudeDesktopSessionLinkMetadata]
        if let claudeCache, claudeCache.signature == signature {
            records = claudeCache.records
        } else {
            records = urls.compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(ClaudeDesktopSessionLinkMetadata.self, from: data)
            }
            claudeCache = (signature, records)
        }
        return Self.focus(from: records, isLook: claudeWasFrontmost)
    }

    /// Claude Desktop stamps `lastFocusedAt` on the conversation its window shows whenever the
    /// window comes into view, including behind another app (seen when another app came to the
    /// front over a third). A stamp counts as a look only when `isLook` confirms Claude was in
    /// front then; any stamp still names the conversation Claude shows.
    static func focus(
        from records: [ClaudeDesktopSessionLinkMetadata], isLook: (Date) -> Bool = { _ in true }
    ) -> ClaudeFocus {
        var focus = ClaudeFocus()
        var latest: (focusedAt: Double, cliIDs: Set<String>)?
        for record in records where record.isArchived != true {
            guard let focusedAt = record.lastFocusedAt else { continue }
            let cliIDs = Set([record.cliSessionId].compactMap { $0 } + (record.priorCliSessionIds ?? []))
            let date = Date(timeIntervalSince1970: focusedAt / 1_000)
            if isLook(date) {
                for cliID in cliIDs where (focus.byCliSessionID[cliID] ?? .distantPast) < date {
                    focus.byCliSessionID[cliID] = date
                }
            }
            if focusedAt > (latest?.focusedAt ?? -1) {
                latest = (focusedAt, cliIDs)
            }
        }
        focus.current = latest?.cliIDs ?? []
        return focus
    }

    private static func metadataURLs(in directory: String) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: directory),
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else { return [] }
        return enumerator.compactMap { entry in
            guard let url = entry as? URL,
                  url.pathExtension == "json",
                  url.lastPathComponent.hasPrefix("local_") else { return nil }
            return url
        }
        .sorted { $0.path < $1.path }
    }
}

/// Which app was in front when, recorded from app activations while AgentTally runs.
final class FrontmostAppHistory {
    /// A focus stamp lands within this long of the activation it belongs to.
    static let tolerance: TimeInterval = 1
    private static let maxChanges = 2_000

    private var changes: [(at: Date, bundleID: String?)]
    /// Nothing is known before this moment.
    private var start: Date
    private var observer: NSObjectProtocol?
    private let center: NotificationCenter?

    init(frontmost: String?, now: Date = Date(), center: NotificationCenter? = NSWorkspace.shared.notificationCenter) {
        changes = [(now, frontmost)]
        start = now
        self.center = center
        observer = center?.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.record(app?.bundleIdentifier, at: Date())
        }
    }

    deinit {
        if let observer { center?.removeObserver(observer) }
    }

    func record(_ bundleID: String?, at date: Date) {
        changes.append((date, bundleID))
        guard changes.count > Self.maxChanges else { return }
        changes.removeFirst(changes.count - Self.maxChanges)
        start = changes[0].at
    }

    /// Whether the app was in front at some moment within the tolerance of `date`. A moment the
    /// history does not cover answers false.
    func wasFrontmost(_ bundleID: String, around date: Date) -> Bool {
        let from = date.addingTimeInterval(-Self.tolerance)
        let until = date.addingTimeInterval(Self.tolerance)
        guard from >= start else { return false }
        for (index, change) in changes.enumerated() where change.bundleID == bundleID {
            let end = index + 1 < changes.count ? changes[index + 1].at : .distantFuture
            if change.at <= until && end >= from { return true }
        }
        return false
    }
}

/// Path, size, and modification time: enough to tell whether a file changed since the last read.
private struct FileSignature: Equatable {
    let path: String
    let size: Int
    let modified: Date

    init?(path: String) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let modified = attributes[.modificationDate] as? Date else { return nil }
        self.path = path
        self.size = (attributes[.size] as? NSNumber)?.intValue ?? -1
        self.modified = modified
    }
}
