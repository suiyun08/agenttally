import SwiftUI
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

    // MARK: - When they show

    func testASessionThatNewlyNeedsTheUserOrFinishesAlerts() {
        var board = SessionToastBoard()
        XCTAssertFalse(board.update([toast("a", .needsYou), toast("b", .working)]), "Not at launch")
        XCTAssertFalse(board.update([toast("a", .needsYou), toast("b", .working, title: "More")]), "Nothing new")
        XCTAssertTrue(board.update([toast("a", .needsYou), toast("b", .done)]), "b finished")
        XCTAssertTrue(board.update([toast("a", .needsYou), toast("b", .done), toast("c", .needsYou)]), "c is new and waits")
        XCTAssertFalse(board.update([toast("a", .working), toast("b", .done), toast("c", .needsYou)]), "Back to work is no alert")
        board.close("c")
        XCTAssertFalse(board.update([toast("a", .working), toast("b", .done), toast("c", .needsYou)]), "Closed stays quiet")
        XCTAssertTrue(board.update([toast("a", .working), toast("b", .done), toast("c", .done)]), "c finished: back, alerting")
    }

    func testTheNoticesShowWhilePeekedPinnedOrAlerting() {
        var visibility = SessionToastVisibility()
        XCTAssertFalse(visibility.isVisible(now: now))
        visibility.setPeeking(true)
        XCTAssertTrue(visibility.isVisible(now: now))
        visibility.setPeeking(false)
        XCTAssertFalse(visibility.isVisible(now: now))
        visibility.alert(now: now)
        XCTAssertTrue(visibility.isVisible(now: now.addingTimeInterval(4.9)))
        XCTAssertFalse(visibility.isVisible(now: now.addingTimeInterval(5)), "An alert lasts five seconds")
        visibility.toggle()
        XCTAssertTrue(visibility.pinned)
        XCTAssertTrue(visibility.isVisible(now: now.addingTimeInterval(3600)), "Pinned until clicked again")
    }

    func testAClickOnPinnedNoticesPutsThemAwayUntilThePointerLeaves() {
        var visibility = SessionToastVisibility()
        visibility.setPeeking(true)
        visibility.toggle()
        visibility.toggle()
        XCTAssertFalse(visibility.isVisible(now: now), "Put away even with the pointer on the indicator")
        visibility.setPeeking(true)
        XCTAssertFalse(visibility.isVisible(now: now), "Resting there again does not bring them back")
        visibility.setPeeking(false)
        visibility.setPeeking(true)
        XCTAssertTrue(visibility.isVisible(now: now), "Once the pointer left and came back, they show")
    }

    func testTheyStayOutWhileASessionWaitsForTheUser() {
        var visibility = SessionToastVisibility()
        visibility.setWaiting(["a"])
        XCTAssertTrue(visibility.isVisible(now: now.addingTimeInterval(3600)), "Waiting has no time limit")
        visibility.setWaiting([])
        XCTAssertFalse(visibility.isVisible(now: now), "Answered: they go")
    }

    func testAClickPutsWaitingSessionsAwayUntilAnotherStartsWaiting() {
        var visibility = SessionToastVisibility()
        visibility.setWaiting(["a"])
        visibility.toggle()
        XCTAssertFalse(visibility.isVisible(now: now), "A click puts them away")
        visibility.setWaiting(["a"])
        XCTAssertFalse(visibility.isVisible(now: now), "The same wait stays put away")
        visibility.setWaiting(["a", "b"])
        XCTAssertTrue(visibility.isVisible(now: now), "Another session starts waiting: they show")
        visibility.toggle()
        visibility.setWaiting([])
        visibility.setWaiting(["a"])
        XCTAssertTrue(visibility.isVisible(now: now), "a waits again after it was answered: they show")
    }

    func testLeavingTheIndicatorAfterPuttingThemAwayLetsHoverShowThemAgain() {
        var visibility = SessionToastVisibility()
        visibility.toggle()
        visibility.toggle()
        visibility.pointerLeftIndicator()
        visibility.setPeeking(true)
        XCTAssertTrue(visibility.isVisible(now: now), "Put away by a click with no hover showing, then left: hover works")
    }

    func testEqualTimesKeepOneOrder() {
        var board = startedBoard()
        board.update([toast("b", .working), toast("a", .working)])
        XCTAssertEqual(board.toasts.map(\.id), ["a", "b"])
        board.update([toast("a", .working), toast("b", .working)])
        XCTAssertEqual(board.toasts.map(\.id), ["a", "b"])
    }

    func testUnderThePointerNoticesHoldTheirPlacesAndNewcomersWaitBehindTheCount() {
        var board = startedBoard()
        board.update([toast("a", .working, ago: 1), toast("b", .working, ago: 2), toast("c", .working, ago: 3)])
        XCTAssertEqual(board.visible(limit: 4).map(\.id), ["a", "b", "c"])
        // c works again and d arrives, both newer than the rest, while the pointer rests on them.
        board.update([
            toast("a", .working, ago: 1), toast("b", .working, ago: 2), toast("c", .working, ago: 0),
            toast("d", .needsYou, ago: 0),
        ])
        let held = board.visible(limit: 4, holding: ["a", "b", "c"])
        XCTAssertEqual(held.map(\.id), ["a", "b", "c"], "d does not push the count down under the pointer")
        XCTAssertEqual(board.waitingCount(besides: held), 1)
        XCTAssertEqual(board.visible(limit: 2, holding: ["a", "b", "c"]).map(\.id), ["a", "b"])
        XCTAssertEqual(board.visible(limit: 4).map(\.id), ["c", "d", "a", "b"], "Re-sorted once the pointer leaves")
    }

    func testTheLimitCapsWhatShowsAndCountsTheRest() {
        var board = startedBoard()
        board.update((1...6).map { toast(String($0), .working, ago: TimeInterval($0)) })
        XCTAssertEqual(board.visible(limit: 4).map(\.id), ["1", "2", "3", "4"])
        XCTAssertEqual(board.waitingCount(besides: board.visible(limit: 4)), 2)
        XCTAssertEqual(board.visible(limit: 6).count, 6)
        XCTAssertEqual(board.waitingCount(besides: board.visible(limit: 6)), 0)
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

    func testAllNoticesShowWhenTheyFit() {
        let start = SessionToastLayout.Start(point: NSPoint(x: 40, y: 820), growsDown: true)
        XCTAssertEqual(SessionToastLayout.shownCount(limit: 4, of: 3, start: start, visible: visible), 3)
        XCTAssertEqual(SessionToastLayout.shownCount(limit: 4, of: 9, start: start, visible: visible), 4)
        XCTAssertEqual(SessionToastLayout.shownCount(limit: 10, of: 10, start: start, visible: visible), 10)
    }

    func testWhatDoesNotFitOnScreenWaitsBehindTheCount() {
        let start = SessionToastLayout.Start(point: NSPoint(x: 40, y: 450), growsDown: true)
        let count = SessionToastLayout.shownCount(limit: 10, of: 10, start: start, visible: visible)
        XCTAssertLessThan(count, 10)
        let frames = SessionToastLayout.frames(count: count, overflow: true, start: start, visible: visible)
        XCTAssertGreaterThanOrEqual(frames.overflow?.minY ?? -1, visible.minY, "The count stays on screen")
        XCTAssertTrue(frames.cards.allSatisfy { $0.minY >= visible.minY })
        let growingUp = SessionToastLayout.Start(point: NSPoint(x: 40, y: 400), growsDown: false)
        let upCount = SessionToastLayout.shownCount(limit: 10, of: 10, start: growingUp, visible: visible)
        let upFrames = SessionToastLayout.frames(count: upCount, overflow: true, start: growingUp, visible: visible)
        XCTAssertLessThanOrEqual(upFrames.overflow?.maxY ?? .infinity, visible.maxY)
    }

    func testAStackLongerThanTheScreenScrollsWithinIt() {
        let start = SessionToastLayout.Start(point: NSPoint(x: 40, y: 400), growsDown: true)
        let frames = SessionToastLayout.frames(count: 10, overflow: true, start: start, visible: visible)
        let room = SessionToastLayout.room(from: start, visible: visible)
        XCTAssertEqual(room, 400)
        let length = SessionToastLayout.length(of: frames, start: start)
        XCTAssertEqual(length, 10 * (SessionToastLayout.height + SessionToastLayout.gap) + SessionToastLayout.overflowSize.height)
        let scrolled = SessionToastLayout.scrolled(frames, by: length - room, growsDown: true)
        XCTAssertEqual(scrolled.overflow?.minY, visible.minY, "Scrolled to the end, the chip sits at the screen's edge")
        let viewport = SessionToastLayout.viewport(start: start, visible: visible, minX: 40)
        XCTAssertEqual(viewport, NSRect(x: 40, y: 0, width: SessionToastLayout.width, height: 400))
    }

    func testTheyStayOnScreenBesideAnIndicatorAtTheEdge() {
        let indicator = NSRect(x: 1400, y: 820, width: 30, height: 32)
        let start = SessionToastLayout.start(under: indicator, visible: visible)
        let frames = SessionToastLayout.frames(count: 1, overflow: false, start: start, visible: visible)
        XCTAssertLessThanOrEqual(frames.cards[0].maxX, visible.maxX)
    }

    // MARK: - Clicks

    /// Two notices and the "N more", stacked as the window lays them out.
    private func stackView() -> SessionToastStackView {
        let stack = SessionToastStackView(frame: NSRect(x: 0, y: 0, width: 300, height: 156))
        stack.add(NSView(frame: NSRect(x: 0, y: 92, width: 300, height: 56)), for: .notice("a"))
        stack.add(NSView(frame: NSRect(x: 0, y: 28, width: 300, height: 56)), for: .notice("b"))
        stack.add(NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 28)), for: .overflow)
        return stack
    }

    func testAClickOpensANoticeOrClosesItInItsCorner() {
        let stack = stackView()
        XCTAssertEqual(stack.action(at: NSPoint(x: 100, y: 110)), .open("a"))
        XCTAssertEqual(stack.action(at: NSPoint(x: 290, y: 140)), .close("a"), "Top-right corner")
        XCTAssertEqual(stack.action(at: NSPoint(x: 290, y: 35)), .open("b"), "Bottom-right is not the corner")
        XCTAssertEqual(stack.action(at: NSPoint(x: 60, y: 14)), .overflow)
    }

    func testTheStatusBesideTheCloseButtonStillOpens() {
        let stack = stackView()
        XCTAssertEqual(stack.action(at: NSPoint(x: 271, y: 140)), .open("a"), "The status label's last letter")
        XCTAssertEqual(stack.action(at: NSPoint(x: 290, y: 118)), .open("a"), "The message line's end")
        XCTAssertEqual(stack.action(at: NSPoint(x: 284, y: 132)), .close("a"), "On the close button")
    }

    func testNoticesOnTheirWayOutTakeNoClicks() {
        let stack = stackView()
        stack.takesClicks = false
        XCTAssertNil(stack.action(at: NSPoint(x: 100, y: 110)))
        XCTAssertNil(stack.hitTest(NSPoint(x: 100, y: 110)))
    }

    func testClicksBetweenAndBesideNoticesFallThrough() {
        let stack = stackView()
        XCTAssertNil(stack.action(at: NSPoint(x: 100, y: 88)), "The gap between notices")
        XCTAssertNil(stack.action(at: NSPoint(x: 200, y: 14)), "Beside the N more")
        XCTAssertNil(stack.hitTest(NSPoint(x: 100, y: 88)))
        XCTAssertTrue(stack.hitTest(NSPoint(x: 100, y: 110)) === stack)
    }

    /// Takes the stack's actions for a press at `down` let go at `up`, without moving between.
    private func click(_ stack: SessionToastStackView, down: NSPoint, up: NSPoint) -> [SessionToastStackView.Action] {
        var actions: [SessionToastStackView.Action] = []
        stack.onAction = { actions.append($0) }
        stack.mouseDown(with: mouse(.leftMouseDown, at: down))
        stack.mouseUp(with: mouse(.leftMouseUp, at: up))
        return actions
    }

    private func mouse(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent {
        NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1
        )!
    }

    func testEveryClickActsAgainAfterTheLast() {
        let stack = stackView()
        XCTAssertEqual(click(stack, down: NSPoint(x: 100, y: 110), up: NSPoint(x: 100, y: 110)), [.open("a")])
        XCTAssertEqual(click(stack, down: NSPoint(x: 290, y: 75), up: NSPoint(x: 290, y: 75)), [.close("b")])
        XCTAssertEqual(click(stack, down: NSPoint(x: 100, y: 110), up: NSPoint(x: 100, y: 110)), [.open("a")])
    }

    func testLettingGoOverAnotherNoticeDoesNothing() {
        let stack = stackView()
        XCTAssertEqual(click(stack, down: NSPoint(x: 100, y: 110), up: NSPoint(x: 100, y: 50)), [])
        XCTAssertEqual(click(stack, down: NSPoint(x: 100, y: 110), up: NSPoint(x: 290, y: 140)), [], "Body to corner")
    }

    // MARK: - The window

    @MainActor
    func testWhenANoticeGoesTheOnesAfterItCloseTheGap() {
        let window = SessionToastStackWindow()
        defer { window.orderOut(nil) }
        let start = SessionToastLayout.Start(point: NSPoint(x: 100, y: 800), growsDown: true)
        func entries(_ ids: [String]) -> [SessionToastStackWindow.Entry] {
            let frames = SessionToastLayout.frames(count: ids.count, overflow: false, start: start, visible: visible)
            return zip(ids, frames.cards).map { id, frame in
                SessionToastStackWindow.Entry(item: .notice(id), frame: frame, cornerRadius: 14, content: AnyView(Color.clear))
            }
        }
        let slots = SessionToastLayout.frames(count: 2, overflow: false, start: start, visible: visible).cards
        window.show(entries(["a", "b", "c"]), growsDown: true)
        settle { window.alphaValue == 1 }
        window.show(entries(["a", "c"]), growsDown: true)
        settle { window.frame == slots[0].union(slots[1]) }
        XCTAssertNil(window.stack.items[.notice("b")])
        XCTAssertEqual(window.screenFrame(of: .notice("a")), slots[0])
        XCTAssertEqual(window.screenFrame(of: .notice("c")), slots[1], "c moved up into b's place")
        XCTAssertEqual(window.frame, slots[0].union(slots[1]), "The window shrank to fit")
    }

    /// Runs the window's animations until `done`, or for at most a few seconds on a slow machine.
    private func settle(until done: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !done(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }

    @MainActor
    func testAScrolledStackShowsOnlyItsViewport() {
        let window = SessionToastStackWindow()
        defer { window.orderOut(nil) }
        let start = SessionToastLayout.Start(point: NSPoint(x: 100, y: 400), growsDown: true)
        let frames = SessionToastLayout.frames(count: 8, overflow: false, start: start, visible: visible)
        let entries = zip(0..., frames.cards).map { index, frame in
            SessionToastStackWindow.Entry(
                item: .notice("n\(index)"), frame: frame, cornerRadius: 14, content: AnyView(Color.clear)
            )
        }
        let viewport = SessionToastLayout.viewport(start: start, visible: visible, minX: 100)
        window.show(entries, growsDown: true, viewport: viewport, animated: false)
        XCTAssertEqual(window.frame, viewport)
        XCTAssertEqual(window.screenFrame(of: .notice("n0")), frames.cards[0], "Each notice keeps its place on screen")
    }

    @MainActor
    func testTheNoticesWindowCastsNoShadow() {
        // A window shadow traces every notice with a dark line over light windows and a light
        // one over dark windows; the glass draws its own edge, as on the floating indicator.
        XCTAssertFalse(SessionToastStackWindow().hasShadow)
    }

    // MARK: - Which sessions get one

    func testWorkingSessionsNeedingTheUserAndUnreadResultsGetNotices() {
        XCTAssertEqual(SessionManager.toastKind(for: .mock(status: .working)), .working)
        XCTAssertEqual(SessionManager.toastKind(for: .mock(status: .compacting)), .working)
        XCTAssertEqual(SessionManager.toastKind(for: .mock(status: .waitingPermission)), .needsYou)
        XCTAssertNil(SessionManager.toastKind(for: .mock(status: .idle)))
    }
}
