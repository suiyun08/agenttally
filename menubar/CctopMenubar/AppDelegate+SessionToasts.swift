import AppKit

// MARK: - Floating notices

extension AppDelegate {
    /// The floating notices hang off the floating indicator and stand in for system banners while
    /// it is on; a click jumps to the session as a banner click would, and the notice stays until
    /// it is closed or the session no longer needs it.
    @MainActor func setupSessionToasts() {
        sessionToasts.anchor = { [weak self] in self?.floatingIndicator.visibleFrame }
        sessionToasts.onOpen = { [weak self] id in self?.openSessionToast(id) }
        sessionToasts.onOverflow = { [weak self] in self?.openPanelAtFloatingIndicator() }
        sessionManager.onSessionsUpdated = { [weak self] in self?.refreshSessionToasts() }
        // Shown, hidden, moved, or resized: the notices follow, and start afresh when turned on.
        floatingIndicator.onFrameChanged = { [weak self] in self?.refreshSessionToasts() }
    }

    @MainActor private func refreshSessionToasts() {
        sessionToasts.update(sessionManager.sessionToastCandidates())
    }

    @MainActor private func openSessionToast(_ id: String) {
        guard let target = sessionManager.focusTarget(forCctopSessionID: id) else { return }
        focusTerminal(session: target)
    }

    /// Opens the panel against the floating indicator and keeps it open.
    @MainActor func openPanelAtFloatingIndicator() {
        guard panelMode != .normal, let indicator = floatingIndicator.visibleFrame else { return }
        focusLocation = NSPoint(x: indicator.midX, y: indicator.midY)
        handleEvent(.menubarIconClicked(
            appIsActive: NSApp.isActive, onDifferentScreen: false, panelVisibleInActiveSpace: panelVisibleInActiveSpace
        ))
    }
}
