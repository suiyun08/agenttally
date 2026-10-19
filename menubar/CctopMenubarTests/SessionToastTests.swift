import XCTest
@testable import CctopMenubar

final class SessionToastTests: XCTestCase {
    private func toast(_ id: String, _ status: SessionStatus = .waitingInput, title: String = "Session") -> SessionToast {
        SessionToast(id: id, badge: .cc, title: title, status: status, message: nil)
    }

    // MARK: - Which notices show

    func testANewReasonPostsANoticeNewestFirst() {
        var board = SessionToastBoard()
        board.apply([.post(cctopSessionID: "a")]) { self.toast($0) }
        board.apply([.post(cctopSessionID: "b")]) { self.toast($0) }
        XCTAssertEqual(board.toasts.map(\.id), ["b", "a"])
    }

    func testAChangedReasonReplacesTheSessionsNoticeAndMovesItUp() {
        var board = SessionToastBoard()
        board.apply([.post(cctopSessionID: "a"), .post(cctopSessionID: "b")]) { self.toast($0) }
        board.apply([.post(cctopSessionID: "a")]) { self.toast($0, .done) }
        XCTAssertEqual(board.toasts.map(\.id), ["a", "b"])
        XCTAssertEqual(board.toasts.first?.status, .done)
    }

    func testANoticeGoesWhenItsSessionNoLongerNeedsTheUser() {
        var board = SessionToastBoard()
        board.apply([.post(cctopSessionID: "a"), .post(cctopSessionID: "b")]) { self.toast($0) }
        board.apply([.remove(cctopSessionID: "a")]) { self.toast($0) }
        XCTAssertEqual(board.toasts.map(\.id), ["b"])
        board.refresh { $0 == "b" ? nil : self.toast($0) }
        XCTAssertTrue(board.toasts.isEmpty, "A session that stops needing the user loses its notice")
    }

    func testClosingHidesANoticeUntilANewReason() {
        var board = SessionToastBoard()
        board.apply([.post(cctopSessionID: "a")]) { self.toast($0) }
        board.dismiss("a")
        board.refresh { self.toast($0) }
        XCTAssertTrue(board.toasts.isEmpty, "Closed stays closed while the reason is the same")
        board.apply([.post(cctopSessionID: "a")]) { self.toast($0, .done) }
        XCTAssertEqual(board.toasts.map(\.id), ["a"])
    }

    func testRefreshKeepsTitlesCurrent() {
        var board = SessionToastBoard()
        board.apply([.post(cctopSessionID: "a")]) { self.toast($0, title: "Old") }
        board.refresh { self.toast($0, title: "New") }
        XCTAssertEqual(board.toasts.first?.title, "New")
    }

    func testAtMostFourShowAndTheRestAreCounted() {
        var board = SessionToastBoard()
        let ids = (1...6).map(String.init)
        board.apply(ids.map { .post(cctopSessionID: $0) }) { self.toast($0) }
        XCTAssertEqual(board.visible.map(\.id), ["6", "5", "4", "3"])
        XCTAssertEqual(board.overflowCount, 2)
    }

    // MARK: - Where they sit

    private let visible = NSRect(x: 0, y: 0, width: 1440, height: 870)

    func testUnderAnIndicatorHighOnTheRightTheyStackDownAlignedRight() {
        let anchor = NSRect(x: 1300, y: 820, width: 80, height: 32)
        let frames = SessionToastLayout.frames(count: 2, overflow: true, anchor: anchor, visible: visible)
        XCTAssertEqual(frames.cards[0].maxY, anchor.minY - SessionToastLayout.gap)
        XCTAssertEqual(frames.cards[1].maxY, frames.cards[0].minY - SessionToastLayout.gap)
        XCTAssertEqual(frames.cards[0].maxX, anchor.maxX)
        XCTAssertEqual(frames.overflow?.maxY, frames.cards[1].minY - SessionToastLayout.gap)
        XCTAssertEqual(frames.overflow?.maxX, anchor.maxX)
    }

    func testOverAnIndicatorLowOnTheLeftTheyStackUpAlignedLeft() {
        let anchor = NSRect(x: 40, y: 30, width: 80, height: 32)
        let frames = SessionToastLayout.frames(count: 2, overflow: false, anchor: anchor, visible: visible)
        XCTAssertEqual(frames.cards[0].minY, anchor.maxY + SessionToastLayout.gap)
        XCTAssertEqual(frames.cards[1].minY, frames.cards[0].maxY + SessionToastLayout.gap)
        XCTAssertEqual(frames.cards[0].minX, anchor.minX)
        XCTAssertNil(frames.overflow)
    }

    func testTheyStayOnScreenBesideAnIndicatorAtTheEdge() {
        let anchor = NSRect(x: 1400, y: 820, width: 30, height: 32)
        let frames = SessionToastLayout.frames(count: 1, overflow: false, anchor: anchor, visible: visible)
        XCTAssertLessThanOrEqual(frames.cards[0].maxX, visible.maxX)
        XCTAssertGreaterThanOrEqual(frames.cards[0].minX, visible.minX)
    }
}
