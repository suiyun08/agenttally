import XCTest
@testable import CctopMenubar

final class FloatingIndicatorTests: XCTestCase {
    private let visible = NSRect(x: 0, y: 0, width: 1440, height: 870)
    private let size = NSSize(width: 60, height: 26)

    // MARK: - Where it sits

    func testItStartsTopRightUnderTheMenuBar() {
        let frame = FloatingIndicatorPlacement.defaultFrame(size: size, visible: visible)
        XCTAssertEqual(frame.maxX, visible.maxX - FloatingIndicatorPlacement.margin)
        XCTAssertEqual(frame.maxY, visible.maxY - FloatingIndicatorPlacement.margin)
        XCTAssertEqual(frame.size, size)
    }

    func testItNeverLeavesTheScreen() {
        let offLeftBottom = NSRect(x: -40, y: -10, width: 60, height: 26)
        XCTAssertEqual(FloatingIndicatorPlacement.kept(offLeftBottom, within: visible).origin, .zero)
        let offRightTop = NSRect(x: 1430, y: 860, width: 60, height: 26)
        let kept = FloatingIndicatorPlacement.kept(offRightTop, within: visible)
        XCTAssertEqual(kept.maxX, visible.maxX)
        XCTAssertEqual(kept.maxY, visible.maxY)
    }

    func testItGrowsAwayFromTheScreenEdgeItSitsAgainst() {
        let onRight = NSRect(x: 1300, y: 800, width: 60, height: 26)
        let grownRight = FloatingIndicatorPlacement.resized(onRight, to: NSSize(width: 90, height: 26), within: visible)
        XCTAssertEqual(grownRight.maxX, onRight.maxX, "Against the right side it grows leftward")
        XCTAssertEqual(grownRight.maxY, onRight.maxY)

        let onLeft = NSRect(x: 40, y: 800, width: 60, height: 26)
        let grownLeft = FloatingIndicatorPlacement.resized(onLeft, to: NSSize(width: 90, height: 26), within: visible)
        XCTAssertEqual(grownLeft.minX, onLeft.minX, "Against the left side it grows rightward")
    }

    func testASavedSpotIsKeptOnlyWhileItLandsOnAScreen() {
        let restored = FloatingIndicatorPlacement.restored(originX: 200, topY: 500, size: size, visibleFrames: [visible])
        XCTAssertEqual(restored, NSRect(x: 200, y: 474, width: 60, height: 26))
        XCTAssertNil(
            FloatingIndicatorPlacement.restored(originX: 3000, topY: 500, size: size, visibleFrames: [visible]),
            "A spot on a screen that is gone falls back to the default"
        )
    }

    func testAShortPressIsAClickAndALongerMoveIsADrag() {
        XCTAssertFalse(FloatingIndicatorPlacement.isDrag(from: .zero, to: NSPoint(x: 2, y: 1)))
        XCTAssertTrue(FloatingIndicatorPlacement.isDrag(from: .zero, to: NSPoint(x: 3, y: 0)))
    }

    // MARK: - Glass

    /// The capsule relies on two private settings of AppKit's glass; this fails first when a
    /// macOS update drops them, so the fallback to public glass gets noticed.
    @MainActor
    func testThePrivateGlassSettingsAreStillThere() throws {
        try XCTSkipUnless(PanelSurfaceStyle.liquidGlassAvailable, "Liquid Glass needs macOS 26")
        XCTAssertTrue(SystemGlass.isAvailable)
        if #available(macOS 26.0, *) {
            let glass = try XCTUnwrap(SystemGlass.make(cornerRadius: 13))
            if glass.responds(to: NSSelectorFromString("_variant")) {
                XCTAssertEqual(glass.value(forKey: "_variant") as? Int, SystemGlass.notificationCenter)
            }
            if glass.responds(to: NSSelectorFromString("_subduedState")) {
                XCTAssertEqual(glass.value(forKey: "_subduedState") as? Int, 0)
            }
        }
    }

    // MARK: - Size

    @MainActor
    func testItIsSizedToItsDots() {
        let empty = FloatingIndicatorView.size(for: .zero)
        XCTAssertEqual(empty, NSSize(width: 34, height: FloatingIndicatorView.height))
        let groups = [StatusDotGroup(family: .claude, dots: [.working, .attention])]
        let counts = StatusCounts(permission: 0, attention: 1, working: 1, idle: 0, dotGroups: groups)
        let layoutWidth = StatusDotLayout(groups: groups, metrics: .floating).width
        XCTAssertEqual(FloatingIndicatorView.size(for: counts).width, ceil(layoutWidth + 18))
    }

    // MARK: - Opening the panel from it

    func testThePanelOpensAboveAnIndicatorLowOnTheScreen() throws {
        let screen = ScreenLayout(frame: NSRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: visible)
        let low = NSRect(x: 700, y: 40, width: 60, height: 26)
        let frame = try XCTUnwrap(PanelPositioning.resolveAnchorPosition(
            anchorRect: low, clickLocation: NSPoint(x: low.midX, y: low.midY),
            panelSize: NSSize(width: 320, height: 400), screens: [screen]
        ))
        XCTAssertEqual(frame.minY, low.maxY + PanelPositioning.margin)

        let high = NSRect(x: 700, y: 800, width: 60, height: 26)
        let below = try XCTUnwrap(PanelPositioning.resolveAnchorPosition(
            anchorRect: high, clickLocation: NSPoint(x: high.midX, y: high.midY),
            panelSize: NSSize(width: 320, height: 400), screens: [screen]
        ))
        XCTAssertEqual(below.maxY, high.minY - PanelPositioning.margin, "With room below it opens below, as from the menu bar")
    }
}
