import Foundation

/// Where a session's transcript lives, derived from the session record on the main thread.
enum TimelineSource: Equatable {
    case claude(sessionID: String, projectPath: String, isDesktop: Bool)
    case codex(threadID: String)

    init?(session: SessionData) {
        let id = session.harnessSessionId ?? session.sessionId
        switch session.agentBadge {
        case .cc, .claudeDesktop:
            self = .claude(sessionID: id, projectPath: session.projectPath, isDesktop: session.agentBadge == .claudeDesktop)
        case .codex:
            self = .codex(threadID: id)
        default:
            return nil
        }
    }

    var key: String {
        switch self {
        case .claude(let id, _, _): return "claude:\(id)"
        case .codex(let id): return "codex:\(id)"
        }
    }
}

enum TimelineState: Equatable {
    case loading
    /// No transcript could be read for this session.
    case unavailable
    case entries([TimelineEntry])
}

/// Board timelines for the sessions on screen. Reading happens off the main thread; a growing
/// transcript is read only from where the previous read stopped. Used from the main thread.
final class SessionTimelineStore: ObservableObject {
    @Published private(set) var states: [String: TimelineState] = [:]

    private let reader: SessionTimelineReader
    private let queue = DispatchQueue(label: "cctop.session-timeline", qos: .utility)
    private var isReading = false
    private var queuedSources: [TimelineSource]?

    init(reader: SessionTimelineReader = SessionTimelineReader()) {
        self.reader = reader
    }

    func state(for session: SessionData) -> TimelineState {
        guard let source = TimelineSource(session: session) else { return .unavailable }
        return states[source.key] ?? .loading
    }

    /// Re-reads the given sessions' transcripts. Calls that land mid-read run once it ends.
    func refresh(_ sessions: [SessionData]) {
        let sources = sessions.compactMap(TimelineSource.init(session:))
        guard !isReading else {
            queuedSources = sources
            return
        }
        isReading = true
        queue.async { [reader] in
            let results = reader.read(sources)
            DispatchQueue.main.async { [weak self] in
                self?.finishRead(results)
            }
        }
    }

    private func finishRead(_ results: [String: TimelineState]) {
        if states != results { states = results }
        isReading = false
        if let next = queuedSources {
            queuedSources = nil
            refresh(next)
        }
    }
}

/// Owns per-transcript parse state. Used only on `SessionTimelineStore`'s queue.
final class SessionTimelineReader {
    private struct FileCursor {
        let path: String
        var offset: UInt64 = 0
    }

    private struct ParseState {
        var files: [FileCursor]
        var parser: any TimelineTranscriptParser
    }

    private let claudeProjectsDir: String
    private let claudeDesktopSessionsDir: String
    private let codexSessionsDir: String
    private var parseStates: [String: ParseState] = [:]
    private var priorClaudeSessionIDs: [String: [String]] = [:]

    init(
        claudeProjectsDir: String = SessionTimelineReader.homePath(".claude/projects"),
        claudeDesktopSessionsDir: String = Config.claudeCodeSessionsDir(),
        codexSessionsDir: String = SessionTimelineReader.homePath(".codex/sessions")
    ) {
        self.claudeProjectsDir = claudeProjectsDir
        self.claudeDesktopSessionsDir = claudeDesktopSessionsDir
        self.codexSessionsDir = codexSessionsDir
    }

    func read(_ sources: [TimelineSource]) -> [String: TimelineState] {
        var results: [String: TimelineState] = [:]
        for source in sources {
            results[source.key] = read(source)
        }
        // Sessions no longer shown give back their parse state.
        parseStates = parseStates.filter { results[$0.key] != nil }
        return results
    }

    private func read(_ source: TimelineSource) -> TimelineState {
        if parseStates[source.key] == nil {
            guard let fresh = newParseState(for: source) else { return .unavailable }
            parseStates[source.key] = fresh
        }
        guard var state = parseStates[source.key] else { return .unavailable }
        for index in state.files.indices {
            let cursor = state.files[index]
            guard let next = Self.feedNewLines(path: cursor.path, from: cursor.offset, into: &state.parser) else {
                // The file shrank or vanished: start over on the next read.
                parseStates[source.key] = nil
                return .loading
            }
            state.files[index].offset = next
        }
        parseStates[source.key] = state
        return .entries(SessionTimeline.entries(from: state.parser.rounds))
    }

    private func newParseState(for source: TimelineSource) -> ParseState? {
        switch source {
        case .claude(let sessionID, let projectPath, let isDesktop):
            // Claude Desktop restarts the CLI under a new session ID; the earlier files hold
            // the start of the same conversation.
            let ids = (isDesktop ? priorSessionIDs(of: sessionID) : []) + [sessionID]
            let paths = ids.compactMap { claudeTranscriptPath(sessionID: $0, projectPath: projectPath) }
            guard !paths.isEmpty else { return nil }
            return ParseState(files: paths.map { FileCursor(path: $0) }, parser: ClaudeTranscriptParser())
        case .codex(let threadID):
            guard let path = codexRolloutPath(threadID: threadID) else { return nil }
            return ParseState(files: [FileCursor(path: path)], parser: CodexRolloutParser())
        }
    }

    // MARK: - Locating transcripts

    private func claudeTranscriptPath(sessionID: String, projectPath: String) -> String? {
        let fileName = sessionID + ".jsonl"
        let fm = FileManager.default
        let direct = (claudeProjectsDir as NSString)
            .appendingPathComponent(Self.claudeProjectDirName(projectPath) + "/" + fileName)
        if fm.fileExists(atPath: direct) { return direct }
        // The session may have started in another folder than the one it reports now.
        guard let dirs = try? fm.contentsOfDirectory(atPath: claudeProjectsDir) else { return nil }
        for dir in dirs {
            let path = (claudeProjectsDir as NSString).appendingPathComponent(dir + "/" + fileName)
            if fm.fileExists(atPath: path) { return path }
        }
        return nil
    }

    /// Claude Code names a project folder after its path with every non-alphanumeric
    /// character replaced by "-".
    static func claudeProjectDirName(_ path: String) -> String {
        String(path.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
    }

    private func priorSessionIDs(of cliSessionID: String) -> [String] {
        if let cached = priorClaudeSessionIDs[cliSessionID] { return cached }
        let ids = Self.claudeDesktopPriorSessionIDs(cliSessionID: cliSessionID, baseDir: claudeDesktopSessionsDir)
        priorClaudeSessionIDs[cliSessionID] = ids
        return ids
    }

    /// `priorCliSessionIds` from the Claude Desktop metadata file whose `cliSessionId` matches.
    static func claudeDesktopPriorSessionIDs(cliSessionID: String, baseDir: String) -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: baseDir), includingPropertiesForKeys: nil
        ) else { return [] }
        for case let url as URL in enumerator
        where url.pathExtension == "json" && url.lastPathComponent.hasPrefix("local_") {
            guard let data = try? Data(contentsOf: url),
                  data.range(of: Data(cliSessionID.utf8)) != nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["cliSessionId"] as? String == cliSessionID else { continue }
            return (json["priorCliSessionIds"] as? [String]) ?? []
        }
        return []
    }

    private func codexRolloutPath(threadID: String) -> String? {
        guard let enumerator = FileManager.default.enumerator(atPath: codexSessionsDir) else { return nil }
        let suffix = "-\(threadID).jsonl"
        for case let relative as String in enumerator where relative.hasSuffix(suffix) {
            return (codexSessionsDir as NSString).appendingPathComponent(relative)
        }
        return nil
    }

    // MARK: - Reading

    /// Feeds the complete lines after `offset` to the parser and returns the offset just past
    /// the last newline, so a line still being written is read whole next time. Nil when the
    /// file is gone or shorter than `offset`.
    static func feedNewLines(
        path: String, from offset: UInt64, into parser: inout any TimelineTranscriptParser
    ) -> UInt64? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd(), end >= offset else { return nil }
        guard end > offset else { return offset }
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.readToEnd() else { return nil }

        var lineStart = data.startIndex
        while let newline = data[lineStart...].firstIndex(of: 0x0A) {
            if newline > lineStart {
                parser.consume(line: data[lineStart..<newline])
            }
            lineStart = data.index(after: newline)
        }
        return offset + UInt64(data.distance(from: data.startIndex, to: lineStart))
    }

    static func homePath(_ relative: String) -> String {
        (FileManager.default.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent(relative)
    }
}
