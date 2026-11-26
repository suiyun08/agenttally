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

    // MARK: - Claude transcript

    func testClaudeRoundsShowTheStartOfEachMessage() {
        var parser = ClaudeTranscriptParser()
        feed(&parser, [
            claudeUser("说明开发环境和代码位置，先别动手", uuid: "u1"),
            claudeAssistant("已了解开发环境，等你给任务。\n\n代码在 app 目录下。", uuid: "a1"),
        ])
        XCTAssertEqual(SessionTimeline.entries(from: parser.rounds).map(\.text), [
            "说明开发环境和代码位置，先别动手", "已了解开发环境，等你给任务。",
        ])
    }

    func testClaudeSkipsToolResultsWakeUpsAndCompactSummaries() {
        var parser = ClaudeTranscriptParser()
        feed(&parser, [
            claudeUser("提供素材和任务说明", uuid: "u1"),
            #"{"type":"user","uuid":"t1","message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}"#,
            claudeAssistant("方案好了，文档授权失效需要重新授权。", uuid: "a1"),
            claudeUser("<task-notification>done</task-notification>", uuid: "n1", origin: "task-notification"),
            claudeAssistant("读完文档，方案已更新。", uuid: "a2"),
            claudeUser("This session is being continued from a previous conversation", uuid: "c1", compact: true),
        ])
        // The wake-up reply belongs to the round the user started.
        XCTAssertEqual(SessionTimeline.entries(from: parser.rounds).map(\.text), [
            "提供素材和任务说明", "读完文档，方案已更新。",
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
            claudeAssistant("背景已读完。", uuid: "a1"),
        ])
        // The new CLI session copies the last reply under its original uuid.
        try write(projectDir + "/new.jsonl", [
            claudeAssistant("背景已读完。", uuid: "a1"),
            claudeUser("开始做吧", uuid: "u2"),
            claudeAssistant("代码已推送。", uuid: "a2"),
        ])
        try #"{"cliSessionId":"new","priorCliSessionIds":["old"]}"#
            .write(toFile: desktop + "/local_1.json", atomically: true, encoding: .utf8)

        let reader = SessionTimelineReader(
            claudeProjectsDir: projects, claudeDesktopSessionsDir: tmpDir + "/desktop", codexSessionsDir: tmpDir
        )
        let source = TimelineSource.claude(sessionID: "new", projectPath: "/Users/me/app", isDesktop: true)
        let state = reader.read([source])[source.key]
        XCTAssertEqual(state, .entries([
            TimelineEntry(id: "0u", role: .user, text: "先读背景"),
            TimelineEntry(id: "0a", role: .agent, text: "背景已读完。"),
            TimelineEntry(id: "1u", role: .user, text: "开始做吧"),
            TimelineEntry(id: "1a", role: .agent, text: "代码已推送。"),
        ]))
    }

    // MARK: - Codex rollout

    func testCodexRoundsIgnoreInjectedContext() {
        var parser = CodexRolloutParser()
        feed(&parser, [
            ##"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"# AGENTS.md instructions"}]}}"##,
            #"{"type":"event_msg","payload":{"type":"item_completed","item":{"type":"UserMessage","content":[{"type":"text","text":"生成一张熊猫侠客"}]}}}"#,
            #"{"type":"event_msg","payload":{"type":"task_complete","last_agent_message":"出图了，等你挑。"}}"#,
        ])
        XCTAssertEqual(SessionTimeline.entries(from: parser.rounds).map(\.text), [
            "生成一张熊猫侠客", "出图了，等你挑。",
        ])
    }

    func testCodexThreadIsReadAcrossItsSegmentFiles() throws {
        let thread = "01a2074b-aa3b-7c10-a7b5-20f40b027ae2"
        let day = tmpDir + "/codex/2026/11/23"
        try FileManager.default.createDirectory(atPath: day, withIntermediateDirectories: true)
        try write(day + "/rollout-2026-11-23T02-25-29-\(thread).jsonl", [codexPrompt("导入快捷话术"), codexReply("表格读不到，需要重新授权。")])
        // Re-sent after an interrupted turn: Codex goes on in a new file.
        try write(day + "/rollout-2026-11-23T02-43-16-\(thread)_01a2075b-f2ac-7011-a75a-6aaad7cc42d4.jsonl", [
            codexPrompt("我刚刚授权了"), codexReply("授权生效，已导入。"),
        ])
        // Another thread whose segment id happens to be this thread's id is not part of it.
        try write(day + "/rollout-2026-11-23T03-00-00-01a20800-0000-7000-8000-000000000000_\(thread).jsonl", [
            codexPrompt("别的线程"),
        ])

        let reader = SessionTimelineReader(
            claudeProjectsDir: tmpDir, claudeDesktopSessionsDir: tmpDir, codexSessionsDir: tmpDir + "/codex"
        )
        let source = TimelineSource.codex(threadID: thread)
        XCTAssertEqual(entryTexts(reader.read([source])[source.key]), [
            "导入快捷话术", "表格读不到，需要重新授权。", "我刚刚授权了", "授权生效，已导入。",
        ])

        // A file Codex starts while the board is open is followed too.
        try write(day + "/rollout-2026-11-23T04-10-00-\(thread)_01a2076c-30ad-7323-9365-23eb28a740f5.jsonl", [
            codexPrompt("提交吧"), codexReply("已提交。"),
        ])
        XCTAssertEqual(entryTexts(reader.read([source])[source.key]).suffix(2), ["提交吧", "已提交。"])
    }

    // MARK: - Incremental reading

    func testLineStillBeingWrittenIsReadOnceComplete() throws {
        let path = tmpDir + "/t.jsonl"
        let first = claudeUser("第一条要求", uuid: "u1") + "\n" + String(claudeAssistant("回复完成。", uuid: "a1").prefix(20))
        try first.write(toFile: path, atomically: true, encoding: .utf8)

        var parser: any TimelineTranscriptParser = ClaudeTranscriptParser()
        let offset = try XCTUnwrap(SessionTimelineReader.feedNewLines(path: path, from: 0, into: &parser))
        XCTAssertEqual(parser.rounds.count, 1)
        XCTAssertNil(parser.rounds.first?.reply)

        try (claudeUser("第一条要求", uuid: "u1") + "\n" + claudeAssistant("回复完成。", uuid: "a1") + "\n")
            .write(toFile: path, atomically: true, encoding: .utf8)
        _ = SessionTimelineReader.feedNewLines(path: path, from: offset, into: &parser)
        XCTAssertEqual(parser.rounds.first?.reply, "回复完成。")
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

    private func entryTexts(_ state: TimelineState?) -> [String] {
        guard case .entries(let entries) = state else { return [] }
        return entries.map(\.text)
    }

    private func codexPrompt(_ text: String) -> String {
        #"{"type":"event_msg","payload":{"type":"item_completed","item":{"type":"UserMessage","content":[{"type":"text","text":"\#(text)"}]}}}"#
    }

    private func codexReply(_ text: String) -> String {
        #"{"type":"event_msg","payload":{"type":"task_complete","last_agent_message":"\#(text)"}}"#
    }

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
