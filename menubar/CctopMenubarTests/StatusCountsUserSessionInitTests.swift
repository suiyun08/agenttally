import XCTest
@testable import CctopMenubar

final class StatusCountsUserSessionInitTests: XCTestCase {
    func testEmptyArray_returnsZero() {
        let counts = StatusCounts(userSessions: [])
        XCTAssertEqual(counts.total, 0)
    }

    func testIdle_isNotCounted() {
        // Connected with nothing to do: Idle tab, no dot.
        let userSessions = userSessions(fromDataFixtures: [.mock(status: .idle)])
        let counts = StatusCounts(userSessions: userSessions)
        XCTAssertEqual(counts.total, 0)
        XCTAssertEqual(counts.dotGroups, [])
    }

    func testUnreadDone_countsOnlyUntilSeen() {
        var unread = SessionData.mock(id: "unread", status: .done)
        unread.isUnseenDone = true
        var read = SessionData.mock(id: "read", status: .done)
        read.isUnseenDone = false

        let counts = StatusCounts(userSessions: userSessions(fromDataFixtures: [unread, read]))

        XCTAssertEqual(counts.idle, 1)
        XCTAssertEqual(counts.total, 1)
        XCTAssertEqual(counts.dotGroups, [StatusDotGroup(family: .claude, dots: [.unreadDone])])
    }

    func testDormantSession_isExcludedFromCounts() {
        var session = SessionData.mock(status: .waitingPermission)
        session.lifecycle = .dormant

        let counts = StatusCounts(userSessions: userSessions(fromDataFixtures: [session]))

        XCTAssertEqual(counts.permission, 0)
        XCTAssertEqual(counts.total, 0)
    }

    func testWorking_countsAsWorking() {
        let userSessions = userSessions(fromDataFixtures: [.mock(status: .working)])
        let counts = StatusCounts(userSessions: userSessions)
        XCTAssertEqual(counts.working, 1)
    }

    func testCompacting_countsAsWorking() {
        let userSessions = userSessions(fromDataFixtures: [.mock(status: .compacting)])
        let counts = StatusCounts(userSessions: userSessions)
        XCTAssertEqual(counts.working, 1)
    }

    func testWaitingPermission_countsAsPermission() {
        let userSessions = userSessions(fromDataFixtures: [.mock(status: .waitingPermission)])
        let counts = StatusCounts(userSessions: userSessions)
        XCTAssertEqual(counts.permission, 1)
    }

    func testWaitingInput_countsAsAttention() {
        let userSessions = userSessions(fromDataFixtures: [.mock(status: .waitingInput)])
        let counts = StatusCounts(userSessions: userSessions)
        XCTAssertEqual(counts.attention, 1)
    }

    func testNeedsAttention_countsAsAttention() {
        let userSessions = userSessions(fromDataFixtures: [.mock(status: .needsAttention)])
        let counts = StatusCounts(userSessions: userSessions)
        XCTAssertEqual(counts.attention, 1)
    }

    func testMixedStatuses_aggregatesCorrectly() {
        let userSessions = userSessions(fromDataFixtures: [
            SessionData.mock(id: "1", status: .idle),
            SessionData.mock(id: "2", status: .idle),
            SessionData.mock(id: "3", status: .working),
            SessionData.mock(id: "4", status: .compacting),
            SessionData.mock(id: "5", status: .waitingPermission),
            SessionData.mock(id: "6", status: .waitingInput),
            SessionData.mock(id: "7", status: .needsAttention),
        ])
        let counts = StatusCounts(userSessions: userSessions)
        XCTAssertEqual(counts.idle, 0)  // idle sessions have nothing to look at
        XCTAssertEqual(counts.working, 2)  // working + compacting
        XCTAssertEqual(counts.permission, 1)
        XCTAssertEqual(counts.attention, 2)  // waitingInput + needsAttention
        XCTAssertEqual(counts.total, 5)
        XCTAssertEqual(counts.needsAction, 3)  // permission + attention
    }

    func testRetainedRecords_countSelectedUserSessionOnce() {
        let selectedData = SessionData.mock(id: "selected", status: .working)
        let retainedData = SessionData.mock(id: "retained", status: .waitingPermission)
        let session = userSession(
            identity: .permanent(UUID()),
            display: selectedData,
            records: [selectedData, retainedData]
        )

        let counts = StatusCounts(userSessions: [session])

        XCTAssertEqual(counts.working, 1)
        XCTAssertEqual(counts.permission, 0)
        XCTAssertEqual(counts.total, 1)
    }

    func testDotsGroupByAgentFamilyWithUrgentDotsFirst() {
        var codexDone = SessionData.mock(id: "codex-done", status: .done, source: SessionData.codexSource)
        codexDone.isUnseenDone = true
        let codexWorking = SessionData.mock(id: "codex-working", status: .background, source: SessionData.codexSource)
        let claudeWorking = SessionData.mock(id: "cc-working", status: .working, pid: 1)
        let claudePermission = SessionData.mock(id: "cc-permission", status: .waitingPermission, pid: 2)
        let opencode = SessionData.mock(id: "oc", status: .needsAttention, pid: 3, source: SessionData.opencodeSource)
        let pi = SessionData.mock(id: "pi", status: .working, pid: 4, source: SessionData.piSource)
        let dsh = SessionData.mock(id: "dsh", status: .working, pid: 5, source: SessionData.dshSource)
        let aider = SessionData.mock(id: "aider", status: .working, pid: 6, source: "aider")

        let counts = StatusCounts(userSessions: userSessions(fromDataFixtures: [
            codexDone, codexWorking, claudeWorking, claudePermission, opencode, pi, dsh, aider,
        ]))

        // One group per agent, each headed by its mark; agents without one come last, by name.
        XCTAssertEqual(counts.dotGroups, [
            StatusDotGroup(family: .claude, dots: [.permission, .working]),
            StatusDotGroup(family: .codex, dots: [.working, .unreadDone]),
            StatusDotGroup(family: .init(.dsh), dots: [.working]),
            StatusDotGroup(family: .init(.opencode), dots: [.attention]),
            StatusDotGroup(family: .init(.pi), dots: [.working]),
            StatusDotGroup(family: .init(.other("aider")), dots: [.working]),
        ])
    }

    func testClaudeDesktopSharesClaudesGroup() {
        let desktop = StatusDotGroup.Family(.claudeDesktop)
        XCTAssertEqual(desktop, .claude)
        XCTAssertEqual(desktop.badge, .cc)
    }
}

final class StatusDotLayoutTests: XCTestCase {
    func testLayoutHeadsEachGroupWithItsMarkAtMenubarSpacing() {
        let layout = StatusDotLayout(
            groups: [
                StatusDotGroup(family: .claude, dots: [.working, .permission]),
                StatusDotGroup(family: .codex, dots: [.unreadDone]),
            ],
            metrics: .menubar
        )
        // 10pt marks, 3pt from their dots; 6pt dots 3pt apart; 6pt between groups.
        XCTAssertEqual(layout.items, [
            .mark(.cc, xPos: 0, width: 10), .dot(.permission, xPos: 13), .dot(.working, xPos: 22),
            .mark(.codex, xPos: 34, width: 10), .dot(.unreadDone, xPos: 47),
        ])
        XCTAssertEqual(layout.width, 53)
    }

    func testAnAgentWithoutAMarkIsHeadedByItsName() throws {
        let layout = StatusDotLayout(
            groups: [StatusDotGroup(family: .init(.other("aider")), dots: [.working])],
            metrics: .menubar
        )
        guard case .mark(let badge, let xPos, let width) = try XCTUnwrap(layout.items.first) else {
            return XCTFail("expected a mark first")
        }
        XCTAssertEqual(badge, .other("aider"))
        XCTAssertEqual(xPos, 0)
        XCTAssertGreaterThan(width, StatusDotMetrics.menubar.markHeight)
    }

    func testLayoutCapsEachGroupAndCountsTheRest() throws {
        let layout = StatusDotLayout(
            groups: [StatusDotGroup(family: .claude, dots: Array(repeating: .working, count: 8))],
            metrics: .menubar
        )
        let dots = layout.items.filter { if case .dot = $0 { return true }; return false }
        XCTAssertEqual(dots.count, StatusDotGroup.defaultMaxVisibleDots)
        guard case .overflow(let text, let xPos, let width) = try XCTUnwrap(layout.items.last) else {
            return XCTFail("expected an overflow label")
        }
        XCTAssertEqual(text, "+2")
        XCTAssertEqual(xPos, 66) // 13pt mark lead, six 6pt dots 3pt apart, 2pt gap
        XCTAssertEqual(layout.width, xPos + width)
    }

    func testMaxWidthShrinksVisibleDotsUntilTheLayoutFits() throws {
        let groups = [StatusDotGroup(family: .claude, dots: Array(repeating: .working, count: 8))]
        let full = StatusDotLayout(groups: groups, metrics: .notch)
        let capped = StatusDotLayout(groups: groups, metrics: .notch, maxWidth: 30)
        XCTAssertGreaterThan(full.width, 30)
        XCTAssertLessThanOrEqual(capped.width, 30)
        let visible = capped.items.filter { if case .dot = $0 { return true }; return false }.count
        guard case .overflow(let text, _, _) = try XCTUnwrap(capped.items.last) else {
            return XCTFail("expected an overflow label")
        }
        XCTAssertEqual(text, "+\(8 - visible)")
    }
}

