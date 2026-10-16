import XCTest
@testable import CctopMenubar

@MainActor
final class MenubarIconRendererTests: XCTestCase {
    private func counts(_ groups: [StatusDotGroup]) -> StatusCounts {
        StatusCounts(permission: 0, attention: 0, working: 0, idle: 0, dotGroups: groups)
    }

    // MARK: - Nothing worth a look (template line)

    func testNoDots_returnsShortTemplateLine() {
        let image = MenubarIconRenderer.render(counts: .zero)
        XCTAssertTrue(image.isTemplate, "With no dots the icon is a template line")
        XCTAssertEqual(image.size.width, 14)
        XCTAssertEqual(image.size.height, 18)
    }

    func testCountsWithoutDots_stillRenderTheTemplateLine() {
        // Read results and idle sessions get no dot, whatever the counts say.
        let image = MenubarIconRenderer.render(counts: StatusCounts(permission: 0, attention: 0, working: 0, idle: 5))
        XCTAssertTrue(image.isTemplate)
    }

    // MARK: - Dots

    func testDotsImage_isColoredAndSizedToItsLayout() {
        let groups = [StatusDotGroup(family: .claude, dots: [.working, .permission])]
        let image = MenubarIconRenderer.render(counts: counts(groups))
        XCTAssertFalse(image.isTemplate)
        XCTAssertEqual(
            image.size.width,
            StatusDotLayout(groups: groups, metrics: .menubar).width + MenubarIconRenderer.pillPadding * 2
        )
        XCTAssertEqual(image.size.height, 18)
    }

    func testWidthGrowsWithSessionsAndAgents() {
        let one = MenubarIconRenderer.render(counts: counts([StatusDotGroup(family: .claude, dots: [.working])]))
        let two = MenubarIconRenderer.render(counts: counts([StatusDotGroup(family: .claude, dots: [.working, .working])]))
        let split = MenubarIconRenderer.render(counts: counts([
            StatusDotGroup(family: .claude, dots: [.working, .working]),
            StatusDotGroup(family: .codex, dots: [.working]),
        ]))
        XCTAssertLessThan(one.size.width, two.size.width)
        XCTAssertLessThan(two.size.width, split.size.width)
    }

    func testLiveImageResolvesStatusColorForCurrentDrawingAppearance() {
        let image = MenubarIconRenderer.render(counts: counts([StatusDotGroup(family: .claude, dots: [.working])]))
        let darkAppearance = NSAppearance(named: .darkAqua)!
        let lightAppearance = NSAppearance(named: .aqua)!

        let darkPixel = dotCenterPixel(in: image, appearance: darkAppearance)
        let lightPixel = dotCenterPixel(in: image, appearance: lightAppearance)

        assertColor(darkPixel, equals: StatusColors.color(for: .working, appearance: darkAppearance))
        assertColor(lightPixel, equals: StatusColors.color(for: .working, appearance: lightAppearance))
        XCTAssertNotEqual(sRGBComponents(darkPixel), sRGBComponents(lightPixel))
    }

    func testUnreadDoneIsAHollowRing() {
        let image = MenubarIconRenderer.render(counts: counts([StatusDotGroup(family: .codex, dots: [.unreadDone])]))
        let light = NSAppearance(named: .aqua)!
        assertColor(
            dotCenterPixel(in: image, appearance: light),
            equals: pixel(in: image, appearance: light, xPos: MenubarIconRenderer.pillPadding / 2),
            "The pill shows through the ring's center"
        )
    }

    func testBreathingLeavesAWaitingDotHollowForItsFadingFill() {
        let groups = [StatusDotGroup(family: .codex, dots: [.attention])]
        let light = NSAppearance(named: .aqua)!
        let still = MenubarIconRenderer.render(counts: counts(groups))
        let breathing = MenubarIconRenderer.render(counts: counts(groups), breathing: true)
        assertColor(dotCenterPixel(in: still, appearance: light), equals: StatusColors.color(for: .attention, appearance: light))
        assertColor(
            dotCenterPixel(in: breathing, appearance: light),
            equals: pixel(in: breathing, appearance: light, xPos: MenubarIconRenderer.pillPadding / 2),
            "The pill shows through the ring until the fill fades in"
        )
    }

    func testBreathingLeavesRunningWorkSolid() {
        let light = NSAppearance(named: .aqua)!
        let image = MenubarIconRenderer.render(
            counts: counts([StatusDotGroup(family: .claude, dots: [.working])]), breathing: true
        )
        assertColor(dotCenterPixel(in: image, appearance: light), equals: StatusColors.color(for: .working, appearance: light))
    }

    func testDotsSitOnATranslucentPill() {
        let image = MenubarIconRenderer.render(counts: counts([StatusDotGroup(family: .claude, dots: [.working])]))
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let alpha = sRGBComponents(pixel(
                in: image, appearance: NSAppearance(named: name)!, xPos: MenubarIconRenderer.pillPadding / 2
            ))[3]
            XCTAssertGreaterThan(alpha, 0.2, "\(name.rawValue): the pill is visible")
            XCTAssertLessThan(alpha, 0.9, "\(name.rawValue): the pill stays translucent")
        }
    }

    // MARK: - Helpers

    /// The pixel at the middle of the image's only dot; the agent mark sits to its left.
    private func dotCenterPixel(in image: NSImage, appearance: NSAppearance) -> NSColor {
        let metrics = StatusDotMetrics.menubar
        let dotX = MenubarIconRenderer.pillPadding
            + AgentMark.width(for: .cc, height: metrics.markHeight) + metrics.markGap + metrics.dotDiameter / 2
        return pixel(in: image, appearance: appearance, xPos: dotX)
    }

    /// The pixel on the image's middle row at `xPos`, drawn in `appearance`.
    private func pixel(in image: NSImage, appearance: NSAppearance, xPos: CGFloat) -> NSColor {
        let width = Int(image.size.width)
        let height = Int(image.size.height)
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        appearance.performAsCurrentDrawingAppearance {
            image.draw(
                in: NSRect(origin: .zero, size: image.size),
                from: .zero,
                operation: .copy,
                fraction: 1
            )
        }
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.colorAt(x: Int(xPos), y: height / 2)!
    }

    private func assertColor(
        _ actual: NSColor,
        equals expected: NSColor,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actualComponents = sRGBComponents(actual)
        let expectedComponents = sRGBComponents(expected)
        for index in actualComponents.indices {
            XCTAssertEqual(
                actualComponents[index], expectedComponents[index], accuracy: 0.001, message, file: file, line: line
            )
        }
    }

    private func sRGBComponents(_ color: NSColor) -> [CGFloat] {
        let color = color.usingColorSpace(.sRGB) ?? color
        return [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
    }
}
