import QuartzCore
import XCTest
@testable import CctopMenubar

@MainActor
final class DotBreathingTests: XCTestCase {
    private func counts(_ groups: [StatusDotGroup]) -> StatusCounts {
        StatusCounts(permission: 0, attention: 0, working: 0, idle: 0, dotGroups: groups)
    }

    /// How far apart two phases are around the breath, 0 to 0.5.
    private func distance(_ lhs: Double, _ rhs: Double) -> Double {
        let gap = abs(lhs - rhs)
        return min(gap, 1 - gap)
    }

    // MARK: - Which dots breathe

    func testDotsWaitingOnTheUserBreatheAndRunningWorkHoldsStill() {
        XCTAssertTrue(StatusDotGroup.Dot.permission.breathes)
        XCTAssertTrue(StatusDotGroup.Dot.attention.breathes)
        XCTAssertTrue(StatusDotGroup.Dot.unreadDone.breathes)
        XCTAssertFalse(StatusDotGroup.Dot.working.breathes)
    }

    // MARK: - The breath

    func testABreathEasesFromHollowToSolidAndBackOverThreeSeconds() {
        XCTAssertEqual(DotBreathing.period, 3)
        XCTAssertEqual(DotBreathing.fill(at: 0, phase: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(DotBreathing.fill(at: 0.75, phase: 0), 0.5, accuracy: 1e-9)
        XCTAssertEqual(DotBreathing.fill(at: 1.5, phase: 0), 1, accuracy: 1e-9)
        XCTAssertEqual(DotBreathing.fill(at: 3, phase: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(DotBreathing.fill(at: 10, phase: 0.25), DotBreathing.fill(at: 10.75, phase: 0), accuracy: 1e-9)
    }

    func testNeighbouringDotsBreatheOutOfStepAndKeepTheirStepAcrossRefreshes() {
        let groups = [
            StatusDotGroup(family: .claude, dots: [.permission, .attention, .unreadDone, .unreadDone]),
            StatusDotGroup(family: .codex, dots: [.attention, .unreadDone]),
        ]
        let spots = StatusDotLayout(groups: groups, metrics: .menubar).dotSpots
        XCTAssertEqual(spots, StatusDotLayout(groups: groups, metrics: .menubar).dotSpots)
        XCTAssertTrue(spots.allSatisfy { (0..<1).contains($0.phase) })
        for (lhs, rhs) in zip(spots, spots.dropFirst()) {
            XCTAssertGreaterThanOrEqual(distance(lhs.phase, rhs.phase), 0.2, "\(lhs) and \(rhs) breathe too close together")
        }
    }

    // MARK: - Menu bar

    func testBreathingSpotsSitOnTheWaitingDotsOnly() {
        let groups = [StatusDotGroup(family: .claude, dots: [.permission, .working, .unreadDone])]
        let spots = MenubarIconRenderer.breathingSpots(counts: counts(groups))
        let layoutSpots = StatusDotLayout(groups: groups, metrics: .menubar).dotSpots
        XCTAssertEqual(spots.map(\.dot), [.permission, .unreadDone])
        XCTAssertEqual(spots[0].rect.minX, MenubarIconRenderer.pillPadding + layoutSpots[0].xPos)
        XCTAssertEqual(spots[1].rect.minX, MenubarIconRenderer.pillPadding + layoutSpots[2].xPos)
        XCTAssertEqual(spots[1].phase, layoutSpots[2].phase)
        XCTAssertEqual(spots[0].rect.midY, 9, "Centered in the 18-point image")
    }

    func testIndicatorBreathesOnlyWhileADotWaitsAndMotionIsAllowed() {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 80, height: 22))
        var reduceMotion = false
        let indicator = MenubarIndicator(button: button, reduceMotion: { reduceMotion })

        indicator.show(counts([StatusDotGroup(family: .claude, dots: [.attention, .working, .unreadDone])]))
        XCTAssertEqual(indicator.breathingDotCount, 2)

        indicator.show(counts([StatusDotGroup(family: .claude, dots: [.working])]))
        XCTAssertEqual(indicator.breathingDotCount, 0, "Running work alone holds still")

        reduceMotion = true
        indicator.show(counts([StatusDotGroup(family: .claude, dots: [.attention])]))
        XCTAssertEqual(indicator.breathingDotCount, 0, "Reduce Motion keeps every dot still")
    }

    func testAFillRebuiltMidBreathCarriesOn() {
        let first = DotBreathing.animation(phase: 0.3, now: 100)
        let later = DotBreathing.animation(phase: 0.3, now: 101.2)
        XCTAssertEqual(first.duration, DotBreathing.period)
        XCTAssertEqual(first.repeatCount, .infinity)
        XCTAssertEqual(first.preferredFrameRateRange.preferred, 20, "A slow fade needs no more frames than this")
        // Each fill starts where the absolute-time breath is, so a rebuilt one does not jump.
        XCTAssertEqual(DotBreathing.fill(at: first.timeOffset, phase: 0), DotBreathing.fill(at: 100, phase: 0.3), accuracy: 1e-9)
        XCTAssertEqual(DotBreathing.fill(at: later.timeOffset, phase: 0), DotBreathing.fill(at: 101.2, phase: 0.3), accuracy: 1e-9)
    }
}
