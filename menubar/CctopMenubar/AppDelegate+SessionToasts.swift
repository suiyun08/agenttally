import AppKit

// MARK: - Floating notices

extension AppDelegate {
    /// The floating notices hang off the floating indicator and stand in for system banners while
    /// it is on; a click jumps to the session as a banner click would.
    @MainActor func setupSessionToasts() {
        sessionToasts.anchor = { [weak self] in self?.floatingIndicator.visibleFrame }
        sessionToasts.onOpen = { [weak self] id in self?.openSessionToast(id) }
        sessionToasts.onOverflow = { [weak self] in self?.openPanelAtFloatingIndicator() }
        sessionManager.onAttentionTransitions = { [weak self] actions in
            guard let self else { return }
            self.sessionToasts.apply(actions) { self.sessionManager.sessionToast(forCctopSessionID: $0) }
        }
        floatingIndicator.onFrameChanged = { [weak self] in self?.sessionToasts.layout() }
    }

    @MainActor private func openSessionToast(_ id: String) {
        sessionToasts.dismiss(id)
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
