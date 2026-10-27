import XCTest
@testable import CctopMenubar

/// Feishu bridge (`lark-channel-bridge`) conversations: one short-lived client process per
/// message, kept as one live session while the bot holds the conversation.
final class LarkBridgeSessionTests: XCTestCase {
    private var root: URL!
    private var sessionsDir: String { root.appendingPathComponent("sessions-under-test").path }
    private var bridgeHome: URL { root.appendingPathComponent("lark-channel") }
    private var defaultsSuite: String!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("lark-bridge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: sessionsDir, withIntermediateDirectories: true)
        defaultsSuite = "LarkBridgeSessionTests-\(UUID().uuidString)"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        UserDefaults().removePersistentDomain(forName: defaultsSuite)
        super.tearDown()
    }

    // MARK: - Hook

    private struct Prober: ProcessProbing {
        var pid: UInt32
        var start: TimeInterval
        var alive = true
        func parentPID() -> UInt32 { pid }
        func startTime(pid: UInt32) -> TimeInterval? { start }
        func isAlive(pid: UInt32) -> Bool { alive }
        func commandName(pid: UInt32) -> String? { nil }
        func controllingTTY() -> String? { nil }
    }

    private struct NoNames: SessionNameResolving {
        func codexThreadName(sessionId: String) -> String? { nil }
        func claudeDesktopTitle(cliSessionId: String) -> String? { nil }
        func transcriptSessionName(transcriptPath: String?, sessionId: String) -> String? { nil }
    }

    private let bridgeEnv = ["LARK_CHANNEL": "1", "LARK_CHANNEL_PROFILE": "claude"]
    private let conversation = "86e47cc5-835d-45c1-8a85-7281aebc42b9"

    private func deps(pid: UInt32, start: TimeInterval, env: [String: String]) -> HookDependencies {
        HookDependencies(
            sessionsDir: { self.sessionsDir },
            environment: { env },
            currentBranch: { _ in "main" },
            process: Prober(pid: pid, start: start),
            names: NoNames(),
            logger: HookLogger(logsDir: root.appendingPathComponent("logs").path)
        )
    }

    private func hook(_ event: String, pid: UInt32, start: TimeInterval, env: [String: String]) throws {
        let json = #"{"session_id":"\#(conversation)","cwd":"/tmp/project","hook_event_name":"\#(event)"}"#
        let input = try JSONDecoder().decode(HookInput.self, from: Data(json.utf8))
        try HookHandler.handleHook(hookName: event, input: input, deps: deps(pid: pid, start: start, env: env))
    }

    private func record(_ name: String) throws -> SessionData {
        try SessionData.fromFile(path: (sessionsDir as NSString).appendingPathComponent(name))
    }

    func testReadsTheBridgeMarkersOnly() {
        XCTAssertEqual(HookHandler.larkChannelProfile(environment: bridgeEnv), "claude")
        XCTAssertNil(HookHandler.larkChannelProfile(environment: ["LARK_CHANNEL_PROFILE": "claude"]))
        XCTAssertNil(HookHandler.larkChannelProfile(environment: ["LARK_CHANNEL": "1", "LARK_CHANNEL_PROFILE": "../x"]))
        XCTAssertNil(HookHandler.larkChannelProfile(environment: [:]))
    }

    func testABridgeConversationKeepsOneRecordAcrossMessages() throws {
        try hook("SessionStart", pid: 100, start: 1000, env: bridgeEnv)
        try hook("Stop", pid: 100, start: 1000, env: bridgeEnv)
        try hook("SessionEnd", pid: 100, start: 1000, env: bridgeEnv)
        let first = try record("lark-\(conversation).json")
        XCTAssertEqual(first.larkChannelProfile, "claude")
        XCTAssertEqual(first.status, .done)
        XCTAssertNil(first.endedAt, "The client process ended after the message; the conversation did not")

        // The next message runs in a new process.
        try hook("SessionStart", pid: 200, start: 2000, env: bridgeEnv)
        let second = try record("lark-\(conversation).json")
        XCTAssertEqual(second.pid, 200)
        XCTAssertEqual(second.cctopSessionId, first.cctopSessionId)
        XCTAssertFalse(FileManager.default.fileExists(atPath: (sessionsDir as NSString).appendingPathComponent("200.json")))
    }

    func testOtherSessionsKeepTheirFileNames() throws {
        let claude = try JSONDecoder().decode(HookInput.self, from: Data(#"{"session_id":"s","cwd":"/p","hook_event_name":"Stop"}"#.utf8))
        let codex = try JSONDecoder().decode(
            HookInput.self, from: Data(#"{"session_id":"s","cwd":"/p","hook_event_name":"Stop","harness_name":"codex"}"#.utf8)
        )
        XCTAssertEqual(sessionFileName(input: claude, pid: 7, safeSessionId: "s"), "7.json")
        XCTAssertEqual(sessionFileName(input: claude, pid: 7, safeSessionId: "s", larkChannelProfile: "claude"), "lark-s.json")
        XCTAssertEqual(sessionFileName(input: codex, pid: 7, safeSessionId: "s", larkChannelProfile: "codex"), "codex-s.json")
    }

    func testANewSessionInTheSameProjectLeavesBridgeConversationsAlone() throws {
        try hook("SessionStart", pid: 100, start: 1000, env: bridgeEnv)
        HookHandler.cleanupSessionsForProject(
            sessionsDir: sessionsDir, projectPath: "/tmp/project", currentPid: 300,
            process: Prober(pid: 300, start: 3000, alive: false),
            logger: HookLogger(logsDir: root.appendingPathComponent("logs").path)
        )
        XCTAssertNoThrow(try record("lark-\(conversation).json"))
    }

    // MARK: - Bridge files

    private func write(_ object: Any, to path: String) throws {
        let url = bridgeHome.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: object).write(to: url)
    }

    private func writeBridge(claudePid: Int = 61848) throws {
        try write(["entries": [
            ["pid": claudePid, "profileName": "claude", "startedAt": "2026-10-23T10:38:59.395Z"],
        ]], to: "registry/processes.json")
        try write([
            "oc_09f77c72fe3f72891d4913c3209db3a2:omt_19bb4236868e9a77": ["sessionId": conversation, "cwd": "/tmp/project"],
        ], to: "profiles/claude/sessions.json")
        try write([
            ["scopeId": "oc_9b6b8a3da4983bd595222d0206a07356", "threadId": "01a1717c", "status": "active"],
        ], to: "profiles/codex/sessions.json.catalog.json")
    }

    /// Started a minute before the bridge registered itself.
    private let bridgeStart = ISO8601DateFormatter().date(from: "2026-10-23T10:37:59Z")!.timeIntervalSince1970

    private func session(profile: String, id: String, status: SessionStatus, codex: Bool = false) -> SessionData {
        var session = SessionData.mock(
            id: id, harnessSessionId: id, status: status, pid: 999, terminal: nil, source: codex ? "codex" : nil
        )
        session.larkChannelProfile = profile
        session.lastActivity = Date().addingTimeInterval(-3600)
        return session
    }

    func testARunningBotHoldsItsConversations() throws {
        try writeBridge()
        let lookup = LarkBridgeLookup(home: bridgeHome, processStartTime: { _ in self.bridgeStart })
        let snapshot = lookup.snapshot(now: Date())
        XCTAssertTrue(snapshot.holds(session(profile: "claude", id: conversation, status: .done)))
        XCTAssertFalse(snapshot.holds(session(profile: "claude", id: "another", status: .done)))
        XCTAssertFalse(snapshot.holds(session(profile: "codex", id: "01a1717c", status: .done, codex: true)),
                       "The codex bot is not registered as running")
    }

    func testABotThatStoppedKeepsItsConversationsOnlyForTheRestartGrace() throws {
        try writeBridge()
        var running = true
        let lookup = LarkBridgeLookup(home: bridgeHome, processStartTime: { _ in running ? self.bridgeStart : nil })
        let now = Date()
        let held = session(profile: "claude", id: conversation, status: .done)
        XCTAssertTrue(lookup.snapshot(now: now).holds(held))
        running = false
        XCTAssertTrue(lookup.snapshot(now: now.addingTimeInterval(LarkBridgeLookup.restartGrace - 1)).holds(held))
        XCTAssertFalse(lookup.snapshot(now: now.addingTimeInterval(LarkBridgeLookup.restartGrace + 1)).holds(held))
    }

    func testAReusedProcessIDIsNotTheBot() throws {
        try writeBridge()
        let lookup = LarkBridgeLookup(home: bridgeHome, processStartTime: { _ in self.bridgeStart + 86_400 })
        XCTAssertFalse(lookup.snapshot(now: Date()).holds(session(profile: "claude", id: conversation, status: .done)))
    }

    func testFindsTheChatAndTopicHoldingAConversation() throws {
        try writeBridge()
        XCTAssertEqual(
            LarkBridgeLookup.chat(profile: "claude", conversationID: conversation, home: bridgeHome),
            LarkChat(chatID: "oc_09f77c72fe3f72891d4913c3209db3a2", threadID: "omt_19bb4236868e9a77")
        )
        XCTAssertEqual(
            LarkBridgeLookup.chat(profile: "codex", conversationID: "01a1717c", home: bridgeHome),
            LarkChat(chatID: "oc_9b6b8a3da4983bd595222d0206a07356"),
            "A conversation outside a topic"
        )
        XCTAssertNil(LarkBridgeLookup.chat(profile: "claude", conversationID: "unknown", home: bridgeHome))
        XCTAssertNil(LarkBridgeLookup.chat(profile: "../registry", conversationID: conversation, home: bridgeHome))
    }

    func testOpensTheTopicOrTheChat() {
        XCTAssertEqual(
            LarkChat(scope: "oc_09f7:omt_19bb")?.url?.absoluteString,
            "lark://applink.feishu.cn/client/thread/open?open_chat_id=oc_09f7&open_thread_id=omt_19bb"
        )
        XCTAssertEqual(
            LarkChat(scope: "oc_09f7")?.url?.absoluteString,
            "lark://applink.feishu.cn/client/chat/open?openChatId=oc_09f7"
        )
        for scope in ["oc_09f7:omt_1&x=2", "oc_09f7:", "oc_09f7:ou_1"] {
            XCTAssertEqual(LarkChat(scope: scope), LarkChat(chatID: "oc_09f7"), "\(scope): no topic, still the chat")
        }
        for scope in ["oc_x&y=1", "omt_19bb", ""] {
            XCTAssertNil(LarkChat(scope: scope), scope)
        }
    }

    // MARK: - Lifecycle

    private func lifecycle(_ session: SessionData, keepsLive: Bool, now: Date = Date()) -> SessionLifecycle {
        SessionLifecyclePolicy.lifecycle(
            for: session, hostClass: session.hostClass, processAlive: false, now: now,
            windows: SessionManager.lifecycleWindows, bridgeKeepsLive: keepsLive
        )
    }

    func testABridgeConversationStaysLiveBetweenMessagesWhileItsBotKeepsIt() {
        let claude = session(profile: "claude", id: conversation, status: .done)
        XCTAssertEqual(lifecycle(claude, keepsLive: true), .active)
        XCTAssertEqual(lifecycle(claude, keepsLive: false), .finished, "Let go: it goes to Recent")
        let codex = session(profile: "codex", id: "01a1717c", status: .done, codex: true)
        XCTAssertEqual(lifecycle(codex, keepsLive: true), .active)
        XCTAssertEqual(lifecycle(codex, keepsLive: false), .dormant)

        var justFinished = claude
        justFinished.lastActivity = Date().addingTimeInterval(-60)
        XCTAssertEqual(lifecycle(justFinished, keepsLive: false), .active, "Quiet for less than the active window")
    }

    func testOnlyAConversationWithSomethingForTheUserKeepsItsBotsHold() throws {
        try writeBridge()
        let bridge = LarkBridgeLookup(home: bridgeHome, processStartTime: { _ in self.bridgeStart }).snapshot(now: Date())
        let seen = SessionSeenStore(defaults: UserDefaults(suiteName: defaultsSuite)!)
        let done = session(profile: "claude", id: conversation, status: .done)
        XCTAssertTrue(SessionManager.bridgeKeepsLive(done, bridge: bridge, seen: seen), "An unread result")
        XCTAssertTrue(SessionManager.bridgeKeepsLive(session(profile: "claude", id: conversation, status: .working),
                                                     bridge: bridge, seen: seen))
        seen.markSeen(cctopSessionID: done.cctopSessionId!, at: Date())
        XCTAssertFalse(SessionManager.bridgeKeepsLive(done, bridge: bridge, seen: seen), "Read and quiet")
        XCTAssertFalse(SessionManager.bridgeKeepsLive(session(profile: "claude", id: "another", status: .working),
                                                      bridge: bridge, seen: seen), "The bot no longer holds it")
    }

    func testCodexDesktopsReadStateLeavesABridgedThreadUnread() {
        var codex = session(profile: "codex", id: "01a1717c", status: .done, codex: true)
        codex.statusChangedAt = Date().addingTimeInterval(-60)
        let desktopWroteAfterwards = ClientReadSnapshot(
            codexUnread: ClientReadSnapshot.CodexUnread(threadIDs: [], writtenAt: Date())
        )
        XCTAssertFalse(ClientReadPolicy.seenInClient(codex, snapshot: desktopWroteAfterwards),
                       "Codex Desktop never lists a bridge's thread, so its silence says nothing")
        codex.larkChannelProfile = nil
        XCTAssertTrue(ClientReadPolicy.seenInClient(codex, snapshot: desktopWroteAfterwards))
    }

    // MARK: - Jump

    func testABridgeConversationOpensItsFeishuTopicOrChat() {
        let bridged = session(profile: "claude", id: conversation, status: .done)
        XCTAssertEqual(
            resolveFocusStrategy(session: bridged, multiplexerOverride: nil, larkChat: LarkChat(scope: "oc_09f7:omt_19bb")),
            .openURL(
                URL(string: "lark://applink.feishu.cn/client/thread/open?open_chat_id=oc_09f7&open_thread_id=omt_19bb")!,
                restoreBundleID: "com.electron.lark"
            )
        )
        XCTAssertEqual(
            resolveFocusStrategy(session: bridged, multiplexerOverride: nil, larkChat: LarkChat(scope: "oc_09f7")),
            .openURL(URL(string: "lark://applink.feishu.cn/client/chat/open?openChatId=oc_09f7")!, restoreBundleID: "com.electron.lark")
        )
        XCTAssertEqual(
            resolveFocusStrategy(session: bridged, multiplexerOverride: nil),
            .activateByBundleID("com.electron.lark"),
            "Without a known chat, Feishu still comes forward"
        )
    }
}
