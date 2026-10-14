import AppKit

// MARK: - Panel geometry and per-screen position
extension AppDelegate {
    /// The screen key for the screen the panel is currently on.
    @MainActor func panelScreenKey() -> String? {
        PanelPositioning.screenKey(forPanelFrame: panel.frame, in: screenLayouts)
    }

    /// The screen key for the screen containing a point.
    func screenKey(at point: NSPoint) -> String? {
        PanelPositioning.screenKey(containing: point, in: screenLayouts)
    }

    private var screenLayouts: [ScreenLayout] {
        NSScreen.screens.map { ScreenLayout($0) }
    }

    @MainActor func positionPanel(animate: Bool = false) {
        guard let size = panelFittingSize() else { return }
        let clickKey = focusLocation.flatMap { screenKey(at: $0) }
            ?? panelScreenKey()
        let clickLocation = focusLocation
        let anchor = anchorRect()
        let screens = screenLayouts
        let frame = screenFittedFrame(fitting: size, screens: screens) { panelSize in
            panelGeometry.showFrame(
                clickScreenKey: clickKey,
                clickLocation: clickLocation,
                anchorRect: anchor,
                panelSize: panelSize,
                screens: screens
            )
        }
        if let frame {
            setPanelFrame(frame, animate: animate)
        }
    }

    /// Resolves a frame for the content's fitting size, shrinks it to the tallest panel its
    /// screen allows, and publishes that limit so the content's lists scroll inside it.
    @MainActor private func screenFittedFrame(
        fitting size: NSSize,
        screens: [ScreenLayout],
        resolve: (NSSize) -> NSRect?
    ) -> NSRect? {
        guard let frame = resolve(size) else { return nil }
        guard let maxHeight = PanelPositioning.maxPanelHeight(forPanelFrame: frame, in: screens) else {
            return frame
        }
        updatePanelHeightLimit(maxHeight)
        guard frame.height > maxHeight else { return frame }
        return resolve(NSSize(width: size.width, height: maxHeight)) ?? frame
    }

    /// Starts the limit at the main screen's full visible height, before the first show measures.
    @MainActor func seedPanelHeightLimit() {
        guard let screen = NSScreen.main else { return }
        panelHeightLimit.maxHeight = PanelPositioning.maxPanelHeight(
            belowTopY: screen.visibleFrame.maxY, on: ScreenLayout(screen)
        )
    }

    /// The content re-measures against a changed limit on its next pass, so resize again then.
    @MainActor private func updatePanelHeightLimit(_ maxHeight: CGFloat) {
        guard abs(panelHeightLimit.maxHeight - maxHeight) > 0.5 else { return }
        panelHeightLimit.maxHeight = maxHeight
        DispatchQueue.main.async { [weak self] in
            self?.resizePanel()
        }
    }

    /// The screen-space rect of the anchor (notch pill or menubar icon).
    @MainActor private func anchorRect() -> NSRect? {
        notchController.pillFrame ?? menubarIconRect()
    }

    /// The screen-space rect of the menubar icon, even when the notch pill
    /// is the anchor (the pill only exists on the built-in screen).
    @MainActor private func menubarIconRect() -> NSRect? {
        guard let button = statusItem.button, let buttonWindow = button.window else { return nil }
        return buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
    }

    /// Reset panel position on double-click. If the panel is on the same screen
    /// as the anchor (menubar icon / notch pill), snap to anchor. Otherwise, snap
    /// under the menubar icon's mirrored position on the panel's current screen
    /// so it doesn't jump across screens.
    @MainActor private func resetPanelToCurrentScreen(animate: Bool = false) {
        guard let size = panelFittingSize() else { return }
        let layouts = screenLayouts
        let panelIdx = PanelPositioning.screenIndex(forPanelFrame: panel.frame, in: layouts)
        let anchor = anchorRect()
        let iconRect = menubarIconRect()
        let frame = screenFittedFrame(fitting: size, screens: layouts) { panelSize in
            PanelPositioning.resolveResetPosition(
                anchorRect: anchor,
                menubarIconRect: iconRect,
                panelScreenIndex: panelIdx,
                panelSize: panelSize,
                screens: layouts
            )
        }
        if let frame {
            setPanelFrame(frame, animate: animate)
        }
    }

    @MainActor func handleScreenChange() {
        screenChangeWork?.cancel()
        suppressResize = true
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.suppressResize = false
            self.hasNotch = NSScreen.builtin?.hasPhysicalNotch == true
            self.refreshStatusDisplay(counts: StatusCounts(userSessions: self.sessionManager.userSessions))
            guard self.panel.isVisible else { return }
            // A click location captured before the debounce must not drive
            // screen-change repositioning; clearing it keeps the key below
            // and positionPanel's internal key identical.
            self.focusLocation = nil
            self.positionPanel(animate: false)
        }
        screenChangeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    @MainActor func resizePanel(animate: Bool = false) {
        guard !suppressResize else { return }
        guard let size = panelFittingSize() else { return }
        // A hidden panel's frame is stale, so only a visible panel re-derives the screen limit.
        let screenMaxHeight = panel.isVisible
            ? PanelPositioning.maxPanelHeight(forPanelFrame: panel.frame, in: screenLayouts)
            : nil
        let maxHeight = screenMaxHeight ?? panelHeightLimit.maxHeight
        let newFrame = panelGeometry.resizedFrame(
            from: panel.frame,
            to: NSSize(width: size.width, height: min(size.height, maxHeight)),
            panelScreenKey: panelScreenKey()
        )
        if let screenMaxHeight {
            updatePanelHeightLimit(screenMaxHeight)
        }
        setPanelFrame(newFrame, animate: animate)
    }

    private func panelFittingSize() -> NSSize? {
        panel.contentView?.layout()
        guard let size = panel.contentView?.fittingSize else { return nil }
        return NSSize(width: max(size.width, 320), height: size.height)
    }

    private func setPanelFrame(_ frame: NSRect, animate: Bool) {
        guard !panel.frame.isNearlyEqual(to: frame) else { return }
        if animate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }
}

private extension NSRect {
    func isNearlyEqual(to other: NSRect) -> Bool {
        abs(origin.x - other.origin.x) < 0.5 &&
            abs(origin.y - other.origin.y) < 0.5 &&
            abs(size.width - other.size.width) < 0.5 &&
            abs(size.height - other.size.height) < 0.5
    }
}

// MARK: - FloatingPanelDelegate
extension AppDelegate: FloatingPanelDelegate {
    @MainActor func panelDidDrag(originX: CGFloat, topY: CGFloat) {
        panelGeometry.saveUserDraggedPosition(
            originX: originX,
            topY: topY,
            panelSize: panel.frame.size,
            screens: screenLayouts
        )
    }

    @MainActor func panelDidRequestReset() {
        panelGeometry.clearUserPosition(forPanelFrame: panel.frame, screens: screenLayouts)
        resetPanelToCurrentScreen(animate: true)
    }
}
