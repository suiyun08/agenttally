import XCTest
@testable import CctopMenubar

final class PanelHoverTests: XCTestCase {
    private func handle(_ event: PanelEvent, mode: PanelMode) -> PanelCoordinator.Result {
        PanelCoordinator.handle(event: event, state: PanelState(mode: mode))
    }

    // MARK: - Opening a peek

    func testRestingOnTheDotsPeeksWithoutTakingFocus() {
        let result = handle(.pointerRested(), mode: .hidden)
        XCTAssertEqual(result.state.mode, .peek)
        XCTAssertEqual(result.actions, [.peekPanel, .startNavKeyMonitor, .postNavAction(.reset)])
        XCTAssertFalse(result.actions.contains(.activateApp), "The app the user is typing in keeps focus")
    }

    func testRestingOnTheDotsLeavesAnOpenPanelAlone() {
        for mode in [PanelMode.normal, .navigate(origin: NavigateOrigin(panelWasClosed: false))] {
            let result = handle(.pointerRested(), mode: mode)
            XCTAssertEqual(result.state.mode, mode)
            XCTAssertTrue(result.actions.isEmpty)
        }
    }

    func testRestingPeeksAPanelLeftOnAnotherSpace() {
        let result = handle(.pointerRested(panelVisibleInActiveSpace: false), mode: .normal)
        XCTAssertEqual(result.state.mode, .peek)
        XCTAssertTrue(result.actions.contains(.peekPanel))
    }

    // MARK: - Pinning and closing

    func testClickingTheDotsPinsAPeekInsteadOfClosingIt() {
        let result = handle(.menubarIconClicked(appIsActive: false), mode: .peek)
        XCTAssertEqual(result.state.mode, .normal)
        XCTAssertEqual(result.actions, [.captureApps, .showPanel, .activateApp, .startNavKeyMonitor, .postNavAction(.reset)])
        XCTAssertFalse(result.actions.contains(.dismissPanel))
    }

    func testKeysInsideAPeekNavigateWithoutPinningIt() {
        let arrow = handle(.navKey(.down), mode: .peek)
        XCTAssertEqual(arrow.state.mode, .peek)
        XCTAssertEqual(arrow.actions, [.postNavAction(.down)])
        let escape = handle(.escape, mode: .peek)
        XCTAssertEqual(escape.state.mode, .peek)
        XCTAssertEqual(escape.actions, [.postNavAction(.escape)])
    }

    func testAPeekStillClosesAfterTheUserJumpsToASession() {
        // Clicking a card jumps to another app; the panel stays a peek and closes on leave.
        var mode = handle(.pointerRested(), mode: .hidden).state.mode
        mode = handle(.appLostFocus, mode: mode).state.mode
        XCTAssertEqual(mode, .peek)
        XCTAssertEqual(handle(.pointerLeft, mode: mode).state.mode, .hidden)
    }

    func testLeavingAPeekClosesIt() {
        let result = handle(.pointerLeft, mode: .peek)
        XCTAssertEqual(result.state.mode, .hidden)
        XCTAssertEqual(result.actions, [.dismissPanel])
    }

    func testLeavingAPinnedPanelKeepsItOpen() {
        let result = handle(.pointerLeft, mode: .normal)
        XCTAssertEqual(result.state.mode, .normal)
        XCTAssertTrue(result.actions.isEmpty)
    }

    func testNavigateShortcutFromAPeekClosesWhenNavigationEnds() {
        let result = handle(.navigateShortcut(), mode: .peek)
        XCTAssertEqual(result.state.mode, .navigate(origin: NavigateOrigin(panelWasClosed: true)))
        XCTAssertTrue(result.actions.contains(.showPanel), "Navigation needs the keyboard, so the panel takes focus")
    }

    func testPeekThenTwoClicksPinsThenCloses() {
        var mode = PanelMode.hidden
        for event in [PanelEvent.pointerRested(), .menubarIconClicked(appIsActive: true), .pointerLeft] {
            mode = handle(event, mode: mode).state.mode
        }
        XCTAssertEqual(mode, .normal, "Moving away after pinning keeps the panel")
        XCTAssertEqual(handle(.menubarIconClicked(appIsActive: true), mode: mode).state.mode, .hidden)
    }

    // MARK: - Where the pointer is

    func testThePointerAgainstTheTopOfTheScreenIsOnTheMenuBar() {
        let statusItem = NSRect(x: 1200, y: 958, width: 60, height: 24)
        XCTAssertTrue(PanelHoverController.contains([statusItem], NSPoint(x: 1230, y: 982)))
        XCTAssertTrue(PanelHoverController.contains([statusItem], NSPoint(x: 1230, y: 970)))
        XCTAssertFalse(PanelHoverController.contains([statusItem], NSPoint(x: 1230, y: 950)))
        XCTAssertFalse(PanelHoverController.contains([statusItem], NSPoint(x: 1100, y: 982)))
    }

    @MainActor
    func testTheFloatingIndicatorOpensWithoutTheMenuBarsPause() {
        let hover = PanelHoverController()
        let menubar = NSView()
        let capsule = NSView()
        hover.track(menubar)
        hover.track(capsule, restDelay: 0)
        let key = PanelHoverController.restDelayKey
        XCTAssertEqual(menubar.trackingAreas.first?.userInfo?[key] as? TimeInterval, PanelHoverController.restDelay)
        XCTAssertEqual(capsule.trackingAreas.first?.userInfo?[key] as? TimeInterval, 0)
    }

    // MARK: - When a peek closes

    func testPeekClosesOnlyAfterThePointerStaysAwayForTheGrace() {
        var tracker = PeekLeaveTracker(grace: 0.5)
        let start = Date(timeIntervalSinceReferenceDate: 0)
        XCTAssertFalse(tracker.shouldClose(pointerInside: false, buttonsPressed: false, now: start))
        XCTAssertFalse(tracker.shouldClose(pointerInside: false, buttonsPressed: false, now: start + 0.4))
        XCTAssertTrue(tracker.shouldClose(pointerInside: false, buttonsPressed: false, now: start + 0.5))
    }

    func testComingBackRestartsTheGrace() {
        var tracker = PeekLeaveTracker(grace: 0.5)
        let start = Date(timeIntervalSinceReferenceDate: 0)
        _ = tracker.shouldClose(pointerInside: false, buttonsPressed: false, now: start)
        XCTAssertFalse(tracker.shouldClose(pointerInside: true, buttonsPressed: false, now: start + 0.3))
        XCTAssertFalse(tracker.shouldClose(pointerInside: false, buttonsPressed: false, now: start + 0.6))
        XCTAssertTrue(tracker.shouldClose(pointerInside: false, buttonsPressed: false, now: start + 1.1))
    }

    func testAHeldButtonNeverClosesThePeek() {
        var tracker = PeekLeaveTracker(grace: 0.5)
        let start = Date(timeIntervalSinceReferenceDate: 0)
        XCTAssertFalse(tracker.shouldClose(pointerInside: false, buttonsPressed: true, now: start))
        XCTAssertFalse(tracker.shouldClose(pointerInside: false, buttonsPressed: true, now: start + 2))
        XCTAssertFalse(tracker.shouldClose(pointerInside: false, buttonsPressed: false, now: start + 2.1))
    }
}
