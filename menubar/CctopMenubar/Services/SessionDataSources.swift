import Foundation

/// The external inputs SessionManager consults while deriving session state: the sessions
/// directory, the Codex/Claude Desktop archive stores, desktop-app liveness, process liveness,
/// notification and manual-visibility preferences, and the clock. Production uses `.live()`; tests override
/// individual fields to run the full pipeline against temp directories, stub lookups, and a
/// deterministic clock. One state-deriving input remains outside this seam:
/// `adjustPermissionStatus` probes the live process tree (`proc_listchildpids`) directly.
struct SessionDataSources {
    var sessionsDir: URL
    var codexThreads: any CodexThreadStateProviding
    var claudeDesktopSessions: any ClaudeDesktopSessionStateProviding
    var desktopAppConnection: DesktopAppConnectionLookup
    var processAlive: (SessionData) -> Bool
    var notificationsEnabled: () -> Bool
    var notificationClient: SessionNotificationClient = .live
    var manualSessionVisibility: ManualSessionVisibilityStore = .live
    var seenSessions: SessionSeenStore = .live
    /// Read state the clients keep themselves. Only `.live()` reads real client files.
    var clientReadState: any ClientReadStateProviding = NoClientReadState()
    var now: () -> Date

    /// A function rather than a stored constant so `Config.sessionsDir()` is resolved
    /// when the caller constructs its sources. The live metadata stores resolve their
    /// own paths as needed, with short internal caches for repeated reads in one pass.
    static func live() -> SessionDataSources {
        SessionDataSources(
            sessionsDir: URL(fileURLWithPath: Config.sessionsDir()),
            codexThreads: CodexThreadArchiveLookup(),
            claudeDesktopSessions: ClaudeDesktopSessionArchiveLookup(),
            desktopAppConnection: .live,
            processAlive: { $0.isAlive },
            notificationsEnabled: { UserDefaults.standard.bool(forKey: "notificationsEnabled") },
            clientReadState: ClientReadStateLookup(),
            now: Date.init
        )
    }
}

/// Remembers when the user last looked at each session (by cctop-owned ID), so a finished
/// turn shows an unread dot and one notification until then. Kept in app preferences, never in
/// hook-owned session files.
struct SessionSeenStore {
    static let defaultsKey = "seenCctopSessionTimes"
    static let live = SessionSeenStore(defaults: .standard)
    /// Entries older than this are dropped on write; a finished turn that old is already idle.
    static let retention: TimeInterval = 14 * 86_400

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    private var seenTimes: [String: TimeInterval] {
        defaults.dictionary(forKey: Self.defaultsKey) as? [String: TimeInterval] ?? [:]
    }

    func seenAt(cctopSessionID: String) -> Date? {
        seenTimes[cctopSessionID].map(Date.init(timeIntervalSince1970:))
    }

    func markSeen(cctopSessionID: String, at date: Date) {
        guard CctopSessionID.isValid(cctopSessionID) else { return }
        let cutoff = date.timeIntervalSince1970 - Self.retention
        var times = seenTimes.filter { $0.value >= cutoff }
        times[cctopSessionID] = date.timeIntervalSince1970
        defaults.set(times, forKey: Self.defaultsKey)
    }

    /// A finished turn is unseen until the user looks at the session after it finished.
    func isUnseen(_ session: SessionData) -> Bool {
        guard session.status == .done, let cctopSessionID = session.cctopSessionId else { return false }
        let finishedAt = session.statusChangedAt ?? session.lastActivity
        guard let seenAt = seenAt(cctopSessionID: cctopSessionID) else { return true }
        return seenAt < finishedAt
    }
}

extension Notification.Name {
    /// Posted on the main thread when the user jumps to a session; `object` is its cctop session ID.
    static let cctopSessionFocused = Notification.Name("cctopSessionFocused")
}
