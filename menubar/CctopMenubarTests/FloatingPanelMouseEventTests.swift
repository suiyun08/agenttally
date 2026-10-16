import XCTest
@testable import CctopMenubar

final class FloatingPanelMouseEventTests: XCTestCase {
    func testPrimesKeyWindowForInactiveBodyMouseDown() {
        XCTAssertTrue(
            FloatingPanel.shouldPrimeKeyWindowBeforeMouseDown(
                isKeyWindow: false,
                isHeaderClick: false
            )
        )
    }

    func testDoesNotPrimeKeyWindowForAlreadyKeyPanel() {
        XCTAssertFalse(
            FloatingPanel.shouldPrimeKeyWindowBeforeMouseDown(
                isKeyWindow: true,
                isHeaderClick: false
            )
        )
    }

    func testDoesNotPrimeKeyWindowForHeaderMouseDown() {
        XCTAssertFalse(
            FloatingPanel.shouldPrimeKeyWindowBeforeMouseDown(
                isKeyWindow: false,
                isHeaderClick: true
            )
        )
    }

    @MainActor
    func testHoveringASideEdgeReportsThatEdgeAndMovingInwardClearsIt() throws {
        final class Recorder: FloatingPanelDelegate {
            var hovered: [PanelResizeEdge?] = []
            func panelDidDrag(originX: CGFloat, topY: CGFloat) {}
            func panelDidRequestReset() {}
            func panelHoveredEdgeDidChange(_ edge: PanelResizeEdge?) { hovered.append(edge) }
            func panelWidthDragDidBegin(edge: PanelResizeEdge) {}
            func panelWidthDragDidMove(to frame: NSRect) {}
            func panelWidthDragDidEnd(at frame: NSRect, edge: PanelResizeEdge) {}
        }
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [], backing: .buffered, defer: true
        )
        panel.contentView = NSView()
        let recorder = Recorder()
        panel.panelDelegate = recorder

        for xPos: CGFloat in [2, 3, 160, 318, 160] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: .mouseMoved, location: NSPoint(x: xPos, y: 100), modifierFlags: [],
                timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                eventNumber: 0, clickCount: 0, pressure: 0
            ))
            panel.mouseMoved(with: event)
        }

        XCTAssertEqual(recorder.hovered, [.leading, nil, .trailing, nil])
    }

    /// The glass lives in its own window; a light or dark choice that skipped it drew light
    /// text on light glass.
    @MainActor
    func testGlassFollowsThePanelsLightOrDarkChoice() {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [], backing: .buffered, defer: true
        )
        panel.appearance = NSAppearance(named: .darkAqua)
        XCTAssertEqual(panel.glassWindow.appearance?.name, .darkAqua)
        panel.appearance = NSAppearance(named: .aqua)
        XCTAssertEqual(panel.glassWindow.appearance?.name, .aqua)
        panel.appearance = nil
        XCTAssertNil(panel.glassWindow.appearance, "Following the system leaves both on the system's choice")
    }
}
