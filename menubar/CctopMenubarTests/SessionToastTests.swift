import XCTest
@testable import CctopMenubar

final class SessionToastTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func toast(
        _ id: String, _ kind: SessionToast.Kind, ago seconds: TimeInterval = 0, title: String = "Session"
    ) -> SessionToast {
        let status: SessionStatus = switch kind {
        case .working: .working
        case .needsYou: .waitingInput
        case .done: .done
        }
        return SessionToast(
            id: id, kind: kind, badge: .cc, title: title, status: status, message: nil,
            lastActivity: now.addingTimeInterval(-seconds)
        )
    }

    /// A board that has seen one refresh already, as after launch.
    private func startedBoard() -> SessionToastBoard {
        var board = SessionToastBoard()
        board.update([])
        return board
    }

    // MARK: - Which notices show

    func testWorkingAndWaitingSessionsShowMostRecentActivityFirst() {
        var board = startedBoard()
        board.update([toast("a", .working, ago: 30), toast("b", .needsYou, ago: 5), toast("c", .done, ago: 10)])
        XCTAssertEqual(board.toasts.map(\.id), ["b", "c", "a"])
    }

    func testANoticeUpdatesInPlaceAsItsSessionMovesOn() {
        var board = startedBoard()
        board.update([toast("a", .working)])
        board.update([toast("a", .needsYou)])
        board.update([toast("a", .done)])
        XCTAssertEqual(board.toasts.map(\.status), [.done])
    }

    func testANoticeGoesWhenItsSessionIsIdleReadOrGone() {
        var board = startedBoard()
        board.update([toast("a", .working), toast("b", .done)])
        board.update([])
        XCTAssertTrue(board.toasts.isEmpty)
    }

    func testAtLaunchLiveSessionsShowButEarlierUnreadResultsDoNot() {
        var board = SessionToastBoard()
        board.update([toast("a", .working), toast("b", .needsYou), toast("c", .done)])
        XCTAssertEqual(Set(board.toasts.map(\.id)), ["a", "b"])
        board.update([toast("a", .working), toast("b", .needsYou), toast("c", .working)])
        XCTAssertEqual(Set(board.toasts.map(\.id)), ["a", "b", "c"], "New work after the result shows")
    }

    // MARK: - Closing

    func testAClosedNoticeStaysClosedWhileItsSessionKeepsWorking() {
        var board = startedBoard()
        board.update([toast("a", .working)])
        board.close("a")
        board.update([toast("a", .working, title: "Still at it")])
        XCTAssertTrue(board.toasts.isEmpty)
    }

    func testAClosedNoticeReturnsWhenItsSessionNeedsTheUserOrFinishes() {
        var board = startedBoard()
        board.update([toast("a", .working)])
        board.close("a")
        board.update([toast("a", .needsYou)])
        XCTAssertEqual(board.toasts.map(\.id), ["a"], "Waiting is a new reason to look")
        board.close("a")
        board.update([toast("a", .working)])
        XCTAssertTrue(board.toasts.isEmpty, "Back to work after an answer is the same work")
        board.update([toast("a", .done)])
        XCTAssertEqual(board.toasts.map(\.id), ["a"], "Finishing is a new reason to look")
    }

    func testAClosedNoticeReturnsWhenItsSessionStartsNewWorkAfterIdling() {
        var board = startedBoard()
        board.update([toast("a", .working)])
        board.close("a")
        board.update([])
        board.update([toast("a", .working)])
        XCTAssertEqual(board.toasts.map(\.id), ["a"])
    }

    func testTheLimitCapsWhatShowsAndCountsTheRest() {
        var board = startedBoard()
        board.update((1...6).map { toast(String($0), .working, ago: TimeInterval($0)) })
        XCTAssertEqual(board.visible(limit: 4).map(\.id), ["1", "2", "3", "4"])
        XCTAssertEqual(board.overflowCount(limit: 4), 2)
        XCTAssertEqual(board.visible(limit: 6).count, 6)
        XCTAssertEqual(board.overflowCount(limit: 6), 0)
    }

    // MARK: - Where they sit

    private let visible = NSRect(x: 0, y: 0, width: 1440, height: 870)

    func testUnderAnIndicatorHighOnScreenTheyStackDownAlignedLeft() {
        let indicator = NSRect(x: 1000, y: 820, width: 120, height: 32)
        let start = SessionToastLayout.start(under: indicator, visible: visible)
        let frames = SessionToastLayout.frames(count: 2, overflow: true, start: start, visible: visible)
        XCTAssertEqual(frames.cards[0].maxY, indicator.minY - SessionToastLayout.gap)
        XCTAssertEqual(frames.cards[1].maxY, frames.cards[0].minY - SessionToastLayout.gap)
        XCTAssertEqual(frames.cards[0].minX, indicator.minX)
        XCTAssertEqual(frames.overflow?.maxY, frames.cards[1].minY - SessionToastLayout.gap)
    }

    func testOverAnIndicatorLowOnScreenTheyStackUp() {
        let indicator = NSRect(x: 40, y: 30, width: 120, height: 32)
        let start = SessionToastLayout.start(under: indicator, visible: visible)
        let frames = SessionToastLayout.frames(count: 2, overflow: false, start: start, visible: visible)
        XCTAssertEqual(frames.cards[0].minY, indicator.maxY + SessionToastLayout.gap)
        XCTAssertEqual(frames.cards[1].minY, frames.cards[0].maxY + SessionToastLayout.gap)
        XCTAssertEqual(frames.cards[0].minX, indicator.minX)
        XCTAssertNil(frames.overflow)
    }

    func testADraggedStackStartsWhereItsFirstNoticeWasLeft() {
        let card = NSRect(x: 500, y: 600, width: SessionToastLayout.width, height: SessionToastLayout.height)
        let start = SessionToastLayout.start(forFirstCard: card, visible: visible)
        let frames = SessionToastLayout.frames(count: 2, overflow: false, start: start, visible: visible)
        XCTAssertEqual(frames.cards[0], card)
        XCTAssertEqual(frames.cards[1].maxY, card.minY - SessionToastLayout.gap)
    }

    func testTheyStayOnScreenBesideAnIndicatorAtTheEdge() {
        let indicator = NSRect(x: 1400, y: 820, width: 30, height: 32)
        let start = SessionToastLayout.start(under: indicator, visible: visible)
        let frames = SessionToastLayout.frames(count: 1, overflow: false, start: start, visible: visible)
        XCTAssertLessThanOrEqual(frames.cards[0].maxX, visible.maxX)
    }

    // MARK: - Which sessions get one

    func testWorkingSessionsNeedingTheUserAndUnreadResultsGetNotices() {
        XCTAssertEqual(SessionManager.toastKind(for: .mock(status: .working)), .working)
        XCTAssertEqual(SessionManager.toastKind(for: .mock(status: .compacting)), .working)
        XCTAssertEqual(SessionManager.toastKind(for: .mock(status: .waitingPermission)), .needsYou)
        XCTAssertNil(SessionManager.toastKind(for: .mock(status: .idle)))
    }
}
