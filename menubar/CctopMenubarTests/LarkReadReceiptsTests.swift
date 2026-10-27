import XCTest
@testable import CctopMenubar

/// A Feishu bridge result counts as read once the user is among the readers of the bot's reply
/// to that turn in Feishu.
final class LarkReadReceiptsTests: XCTestCase {
    private var home: URL!
    private let user = "ou_testuser"
    private let conversation = "5451b271-d36b-439d-b08a-000000000001"
    private let finishedAt = Date().addingTimeInterval(-120)
    private var logs: URL { home.appendingPathComponent("profiles/claude/logs") }
    private var config: URL { home.appendingPathComponent("profiles/claude/lark-cli/lark-channel") }

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("lark-read-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: [
            "apps": [["appId": "cli_test", "users": [["userOpenId": user, "userName": "test"]]]],
        ]).write(to: config.appendingPathComponent("config.json"))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: home)
        super.tearDown()
    }

    // MARK: - Bridge logs

    /// One bridge log line, as `lark-channel-bridge` writes it.
    private func line(_ trace: String, _ phase: String, _ event: String, at offset: TimeInterval, _ fields: String = "") -> String {
        let dates = ISO8601DateFormatter()
        dates.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        dates.timeZone = TimeZone(secondsFromGMT: -4 * 3600)
        let ts = dates.string(from: finishedAt.addingTimeInterval(offset))
        return #"{"ts":"\#(ts)","level":"info","phase":"\#(phase)","event":"\#(event)","traceId":"\#(trace)"\#(fields)}"#
    }

    private func writeLog(_ lines: [String]) throws {
        let days = DateFormatter()
        days.locale = Locale(identifier: "en_US_POSIX")
        days.dateFormat = "yyyyMMdd"
        try (lines.joined(separator: "\n") + "\n")
            .write(to: logs.appendingPathComponent("bridge-\(days.string(from: finishedAt)).jsonl"), atomically: true, encoding: .utf8)
    }

    /// An earlier message's trace, then the trace that ran the turn that just finished.
    private func twoTurns(latestReplies: Bool = true) -> [String] {
        var lines = [
            line("t1", "session", "resume", at: -900, #","sessionId":"\#(conversation)""#),
            line("t1", "outbound", "sent", at: -600, #","messageId":"om_earlier""#),
            line("t2", "flush", "start", at: -300, #","threadId":"omt_19bb""#),
            line("t2", "session", "resume", at: -300, #","sessionId":"\#(conversation)""#),
            line("t2", "cot", "created", at: -299, #","messageId":"om_progress""#),
            line("t2", "session", "set", at: -297, #","sessionId":"\#(conversation)""#),
            line("t3", "session", "set", at: -10, #","sessionId":"another-conversation""#),
            line("t3", "outbound", "sent", at: 5, #","messageId":"om_another""#),
        ]
        if latestReplies {
            lines.append(line("t2", "outbound", "sent", at: 1, #","messageId":"om_attachment""#))
            lines.append(line("t2", "outbound", "sent", at: 2, #","messageId":"om_reply""#))
        }
        return lines
    }

    private func lastReply(_ id: String? = nil) -> String? {
        LarkReadReceipts.lastReply(conversationID: id ?? conversation, finishedAt: finishedAt, logsDirectory: logs)
    }

    func testFindsTheBotsLastReplyToTheTurnThatFinished() throws {
        try writeLog(twoTurns())
        XCTAssertEqual(lastReply(), "om_reply")
    }

    func testWaitsForTheReplyToTheTurnThatFinished() throws {
        try writeLog(twoTurns(latestReplies: false))
        XCTAssertNil(lastReply(), "The previous message's reply is not this turn's")
    }

    func testAReplyFromBeforeTheTurnFinishedIsNotItsReply() throws {
        try writeLog([
            line("t1", "session", "resume", at: -900, #","sessionId":"\#(conversation)""#),
            line("t1", "outbound", "sent", at: -600, #","messageId":"om_earlier""#),
        ])
        XCTAssertNil(lastReply())
    }

    func testACodexTraceNamesItsThreadLast() throws {
        try writeLog([
            line("c1", "flush", "start", at: -60, #","threadId":"omt_198586e5""#),
            line("c1", "session", "resume", at: -60, #","sessionId":"old-thread""#),
            line("c1", "session", "set-thread", at: -58, #","threadId":"new-thread""#),
            line("c1", "outbound", "sent", at: 1, #","messageId":"om_codex""#),
        ])
        XCTAssertEqual(lastReply("new-thread"), "om_codex")
        XCTAssertNil(lastReply("old-thread"), "The resume fell back to a new thread")
    }

    func testReadsTheUserTheBotAnswers() throws {
        XCTAssertEqual(LarkReadReceipts.userOpenID(configDirectory: config), user)
        try JSONSerialization.data(withJSONObject: ["apps": [["users": [["userOpenId": "ou_x/../y"]]]]])
            .write(to: config.appendingPathComponent("config.json"))
        XCTAssertNil(LarkReadReceipts.userOpenID(configDirectory: config))
        XCTAssertNil(LarkReadReceipts.userOpenID(configDirectory: home))
    }

    // MARK: - Checking Feishu

    private final class Readers {
        var answer: Set<String>? = []
        var asked: [(URL, String)] = []
        func callAsFunction(_ directory: URL, _ messageID: String) -> Set<String>? {
            asked.append((directory, messageID))
            return answer
        }
    }

    private func makeReceipts(_ readers: Readers) -> LarkReadReceipts {
        LarkReadReceipts(home: home, readers: { readers($0, $1) }, schedule: { $0() })
    }

    private func result(profile: String? = "claude", status: SessionStatus = .done) -> SessionData {
        var session = SessionData.mock(id: conversation, harnessSessionId: conversation, status: status, terminal: nil)
        session.larkChannelProfile = profile
        session.statusChangedAt = finishedAt
        session.lastActivity = finishedAt
        return session
    }

    func testAResultIsReadOnceTheUserIsAmongTheReadersOfItsReply() throws {
        try writeLog(twoTurns())
        let readers = Readers()
        readers.answer = ["ou_someone_else", user]
        let receipts = makeReceipts(readers)
        receipts.request(result(), now: Date())
        XCTAssertEqual(readers.asked.map(\.1), ["om_reply"])
        XCTAssertEqual(readers.asked.first?.0.standardizedFileURL, config.standardizedFileURL)
        XCTAssertEqual(receipts.readTurnsSnapshot(), [conversation: finishedAt])
    }

    func testAResultOnlyOthersReadStaysUnreadAndIsAskedAgainAMinuteLater() throws {
        try writeLog(twoTurns())
        let readers = Readers()
        readers.answer = ["ou_someone_else"]
        let receipts = makeReceipts(readers)
        let now = Date()
        receipts.request(result(), now: now)
        receipts.request(result(), now: now.addingTimeInterval(LarkReadReceipts.recheckInterval - 1))
        XCTAssertEqual(readers.asked.count, 1, "At most once a minute")
        XCTAssertTrue(receipts.readTurnsSnapshot().isEmpty)

        readers.answer = nil
        receipts.request(result(), now: now.addingTimeInterval(LarkReadReceipts.recheckInterval))
        XCTAssertEqual(readers.asked.count, 2)
        XCTAssertTrue(receipts.readTurnsSnapshot().isEmpty, "Feishu did not answer")

        readers.answer = [user]
        receipts.request(result(), now: now.addingTimeInterval(2 * LarkReadReceipts.recheckInterval))
        XCTAssertEqual(receipts.readTurnsSnapshot(), [conversation: finishedAt])
        receipts.request(result(), now: now.addingTimeInterval(3 * LarkReadReceipts.recheckInterval))
        XCTAssertEqual(readers.asked.count, 3, "A read result is not asked about again")
    }

    func testAStuckCheckIsNotQueuedAgain() throws {
        try writeLog(twoTurns())
        let readers = Readers()
        var pending: [() -> Void] = []
        let receipts = LarkReadReceipts(home: home, readers: { readers($0, $1) }, schedule: { pending.append($0) })
        let now = Date()
        receipts.request(result(), now: now)
        receipts.request(result(), now: now.addingTimeInterval(5 * LarkReadReceipts.recheckInterval))
        XCTAssertEqual(pending.count, 1, "The first check has not come back")
        pending.removeFirst()()
        receipts.request(result(), now: now.addingTimeInterval(6 * LarkReadReceipts.recheckInterval))
        XCTAssertEqual(pending.count, 1)
    }

    func testOnlyAFinishedBridgeResultWithinFeishusReceiptWindowIsChecked() throws {
        try writeLog(twoTurns())
        let readers = Readers()
        let receipts = makeReceipts(readers)
        receipts.request(result(profile: nil), now: Date())
        receipts.request(result(status: .working), now: Date())
        receipts.request(result(profile: "../registry"), now: Date())
        receipts.request(result(), now: finishedAt.addingTimeInterval(LarkReadReceipts.receiptWindow))
        XCTAssertTrue(readers.asked.isEmpty)
    }

    func testNoReplyYetMeansNoQuestionToFeishu() throws {
        try writeLog(twoTurns(latestReplies: false))
        let readers = Readers()
        makeReceipts(readers).request(result(), now: Date())
        XCTAssertTrue(readers.asked.isEmpty)
    }

    // MARK: - Unread dot

    func testTheReadPolicyFollowsTheTurnReadInFeishu() {
        let done = result()
        XCTAssertTrue(ClientReadPolicy.seenInClient(done, snapshot: ClientReadSnapshot(larkReadTurns: [conversation: finishedAt])))
        XCTAssertFalse(ClientReadPolicy.seenInClient(
            done, snapshot: ClientReadSnapshot(larkReadTurns: [conversation: finishedAt.addingTimeInterval(-600)])
        ), "Only an earlier turn was read")
        XCTAssertFalse(ClientReadPolicy.seenInClient(done, snapshot: .empty))
    }

    @MainActor
    func testTheDotClearsAfterTheUserReadsTheReplyInFeishu() throws {
        try writeLog(twoTurns())
        let suiteName = "cctop-lark-read-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var sources = try isolatedSessionDataSources(prefix: "cctop-lark-read")
        let done = result()
        try done.writeToFile(path: sources.sessionsDir.appendingPathComponent("lark-\(conversation).json").path)
        var clock = Date()
        sources.now = { clock }
        sources.processAlive = { _ in true }
        sources.seenSessions = SessionSeenStore(defaults: defaults)
        let readers = Readers()
        readers.answer = ["ou_someone_else"]
        sources.larkReadReceipts = makeReceipts(readers)
        let manager = SessionManager(
            historyManager: HistoryManager(historyDir: sources.sessionsDir.appendingPathComponent("history")),
            dataSources: sources,
            startMonitoring: false
        )
        func unread() -> Bool? { manager.userSessions.first?.displayRecord.data.isUnseenDone }
        XCTAssertEqual(unread(), true, "Not read in Feishu yet")
        XCTAssertEqual(readers.asked.count, 1)

        // The user opens the topic; the next check a minute later finds them among the readers.
        readers.answer = [user]
        clock = clock.addingTimeInterval(LarkReadReceipts.recheckInterval)
        manager.loadSessions()
        XCTAssertEqual(readers.asked.count, 2)
        manager.loadSessions()
        XCTAssertEqual(unread(), false)
        XCTAssertNotNil(SessionSeenStore(defaults: defaults).seenAt(cctopSessionID: try XCTUnwrap(done.cctopSessionId)))
        manager.loadSessions()
        XCTAssertEqual(readers.asked.count, 2, "Nothing left to ask once it is read")
    }
}
