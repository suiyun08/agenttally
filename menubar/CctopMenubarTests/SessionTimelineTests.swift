import XCTest
@testable import CctopMenubar

final class SessionTimelineTests: XCTestCase {
    private var tmpDir: String!

    override func setUp() {
        super.setUp()
        tmpDir = NSTemporaryDirectory() + "cctop-timeline-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tmpDir)
        super.tearDown()
    }

    // MARK: - Summary line

    func testSummaryLineIsReadFromTheEndOfAReply() {
        let reply = "设计稿改好了。\n\n`本轮｜你要：补空状态提示｜我做：已加提示，等你看效果`"
        let line = TurnSummaryLine.parse(reply)
        XCTAssertEqual(line?.asked, "补空状态提示")
        XCTAssertEqual(line?.did, "已加提示，等你看效果")
    }

    func testSummaryLineAcceptsHalfWidthMarks() {
        let line = TurnSummaryLine.parse("本轮 | 你要: 查日志 | 我做: 找到报错原因")
        XCTAssertEqual(line?.asked, "查日志")
        XCTAssertEqual(line?.did, "找到报错原因")
    }

    func testReplyWithoutSummaryLineHasNone() {
        XCTAssertNil(TurnSummaryLine.parse("本轮改了三处。\n下一步等你确认。"))
    }

    // MARK: - Claude transcript

    func testClaudeRoundsUseSummaryLines() {
        var parser = ClaudeTranscriptParser()
        feed(&parser, [
            claudeUser("说明开发环境和代码位置，先别动手", uuid: "u1"),
            claudeAssistant("收到。\n本轮｜你要：说明环境和注意点｜我做：已了解，等你给任务", uuid: "a1"),
        ])
        XCTAssertEqual(SessionTimeline.entries(from: parser.rounds).map(\.text), [
            "说明环境和注意点", "已了解，等你给任务",
        ])
    }

    func testClaudeSkipsToolResultsWakeUpsAndCompactSummaries() {
        var parser = ClaudeTranscriptParser()
        feed(&parser, [
            claudeUser("提供素材和任务说明", uuid: "u1"),
            #"{"type":"user","uuid":"t1","message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}"#,
            claudeAssistant("方案好了。\n本轮｜你要：按素材出方案｜我做：给出方案，文档授权失效", uuid: "a1"),
            claudeUser("<task-notification>done</task-notification>", uuid: "n1", origin: "task-notification"),
            claudeAssistant("后台任务回来了。\n本轮｜你要：无新要求｜我做：读完文档，方案已更新", uuid: "a2"),
            claudeUser("This session is being continued from a previous conversation", uuid: "c1", compact: true),
        ])
        XCTAssertEqual(SessionTimeline.entries(from: parser.rounds).map(\.text), [
            "按素材出方案", "读完文档，方案已更新",
        ])
    }

    func testClaudeRoundWithoutSummaryShowsFirstSentences() {
        var parser = ClaudeTranscriptParser()
        feed(&parser, [
            claudeUser("## 需求\n**现在的头像图片**是选填吗？我觉得应该必填。", uuid: "u1"),
            claudeAssistant("```swift\nlet x = 1\n```\n图片目前是选填。按规范多数场景应必填。", uuid: "a1"),
        ])
        XCTAssertEqual(SessionTimeline.entries(from: parser.rounds).map(\.text), [
            "现在的头像图片是选填吗？", "图片目前是选填。",
        ])
    }

    func testResumedClaudeDesktopSessionReadsEarlierFileOnce() throws {
        let projects = tmpDir + "/projects"
        let desktop = tmpDir + "/desktop/acct/org"
        let projectDir = projects + "/" + SessionTimelineReader.claudeProjectDirName("/Users/me/app")
        try FileManager.default.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: desktop, withIntermediateDirectories: true)
        try write(projectDir + "/old.jsonl", [
            claudeUser("先读背景", uuid: "u1"),
            claudeAssistant("本轮｜你要：读背景｜我做：已读完", uuid: "a1"),
        ])
        // The new CLI session copies the last reply under its original uuid.
        try write(projectDir + "/new.jsonl", [
            claudeAssistant("本轮｜你要：读背景｜我做：已读完", uuid: "a1"),
            claudeUser("开始做吧", uuid: "u2"),
            claudeAssistant("本轮｜你要：开始开发｜我做：代码已推送", uuid: "a2"),
        ])
        try #"{"cliSessionId":"new","priorCliSessionIds":["old"]}"#
            .write(toFile: desktop + "/local_1.json", atomically: true, encoding: .utf8)

        let reader = SessionTimelineReader(
            claudeProjectsDir: projects, claudeDesktopSessionsDir: tmpDir + "/desktop", codexSessionsDir: tmpDir
        )
        let source = TimelineSource.claude(sessionID: "new", projectPath: "/Users/me/app", isDesktop: true)
        let state = reader.read([source])[source.key]
        XCTAssertEqual(state, .entries([
            TimelineEntry(id: "0u", role: .user, text: "读背景"),
            TimelineEntry(id: "0a", role: .agent, text: "已读完"),
            TimelineEntry(id: "1u", role: .user, text: "开始开发"),
            TimelineEntry(id: "1a", role: .agent, text: "代码已推送"),
        ]))
    }

    // MARK: - Codex rollout

    func testCodexRoundsIgnoreInjectedContext() {
        var parser = CodexRolloutParser()
        feed(&parser, [
            ##"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"# AGENTS.md instructions"}]}}"##,
            #"{"type":"event_msg","payload":{"type":"item_completed","item":{"type":"UserMessage","content":[{"type":"text","text":"生成一张熊猫侠客"}]}}}"#,
            #"{"type":"event_msg","payload":{"type":"task_complete","last_agent_message":"出图了。\n本轮｜你要：画熊猫侠客｜我做：已出图，等你挑"}}"#,
        ])
        XCTAssertEqual(SessionTimeline.entries(from: parser.rounds).map(\.text), [
            "画熊猫侠客", "已出图，等你挑",
        ])
    }

    // MARK: - Incremental reading

    func testLineStillBeingWrittenIsReadOnceComplete() throws {
        let path = tmpDir + "/t.jsonl"
        let first = claudeUser("第一条要求", uuid: "u1") + "\n" + String(claudeAssistant("本轮｜你要：x｜我做：y", uuid: "a1").prefix(20))
        try first.write(toFile: path, atomically: true, encoding: .utf8)

        var parser: any TimelineTranscriptParser = ClaudeTranscriptParser()
        let offset = try XCTUnwrap(SessionTimelineReader.feedNewLines(path: path, from: 0, into: &parser))
        XCTAssertEqual(parser.rounds.count, 1)
        XCTAssertNil(parser.rounds.first?.reply)

        try (claudeUser("第一条要求", uuid: "u1") + "\n" + claudeAssistant("本轮｜你要：x｜我做：y", uuid: "a1") + "\n")
            .write(toFile: path, atomically: true, encoding: .utf8)
        _ = SessionTimelineReader.feedNewLines(path: path, from: offset, into: &parser)
        XCTAssertEqual(parser.rounds.first?.did, "y")
    }

    // MARK: - Board columns

    func testEveryActiveStatusHasAColumn() {
        let expected: [SessionStatus: SessionBoardColumnKind] = [
            .waitingPermission: .waiting, .waitingInput: .waiting, .needsAttention: .waiting,
            .working: .working, .compacting: .working,
            .done: .finished,
            .background: .background,
        ]
        for (status, column) in expected {
            XCTAssertEqual(SessionBoardColumnKind(status: status), column, "\(status)")
        }
    }

    func testExpandedCardTakesWhatTheColumnLeaves() {
        // Two collapsed cards of 180 and the expanded card's 70-point header leave 700 - 430 - 12.
        let height = SessionBoardMetrics.expandedTimelineHeight(
            cardsHeight: 700, fixedHeight: 430, expandedCount: 1, cardCount: 3
        )
        XCTAssertEqual(height, 258 - SessionBoardMetrics.timelineChromeHeight)
    }

    func testTwoExpandedCardsShareTheRoom() {
        let one = SessionBoardMetrics.expandedTimelineHeight(cardsHeight: 700, fixedHeight: 140, expandedCount: 2, cardCount: 2)
        XCTAssertEqual(one, (700 - 140 - SessionBoardMetrics.cardSpacing) / 2 - SessionBoardMetrics.timelineChromeHeight)
    }

    func testCrowdedColumnStillGivesAnExpandedCardRoom() {
        let height = SessionBoardMetrics.expandedTimelineHeight(
            cardsHeight: 400, fixedHeight: 600, expandedCount: 1, cardCount: 4
        )
        XCTAssertEqual(height, SessionBoardMetrics.minExpandedTimelineHeight)
    }

    // MARK: - Helpers

    private func feed<P: TimelineTranscriptParser>(_ parser: inout P, _ lines: [String]) {
        for line in lines { parser.consume(line: Data(line.utf8)) }
    }

    private func write(_ path: String, _ lines: [String]) throws {
        try (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func claudeUser(_ text: String, uuid: String, origin: String = "human", compact: Bool = false) -> String {
        let row: [String: Any] = [
            "type": "user", "uuid": uuid, "isCompactSummary": compact,
            "origin": ["kind": origin],
            "message": ["role": "user", "content": text],
        ]
        return jsonLine(row)
    }

    private func claudeAssistant(_ text: String, uuid: String) -> String {
        let row: [String: Any] = [
            "type": "assistant", "uuid": uuid,
            "message": ["role": "assistant", "content": [["type": "text", "text": text]]],
        ]
        return jsonLine(row)
    }

    private func jsonLine(_ object: [String: Any]) -> String {
        // Claude Code writes compact JSON; keep slashes unescaped like it does.
        let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
        return String(data: data ?? Data(), encoding: .utf8) ?? ""
    }
}
