import AppKit

// MARK: - Floating notices

extension AppDelegate {
    /// The floating notices hang off the floating indicator and stand in for system banners while
    /// it is on; a click jumps to the session as a banner click would, and the notice stays until
    /// it is closed or the session no longer needs it.
    @MainActor func setupSessionToasts() {
        sessionToasts.anchor = { [weak self] in self?.floatingIndicator.visibleFrame }
        sessionToasts.onOpen = { [weak self] id in self?.openSessionToast(id) }
        sessionToasts.watchLeave = { [weak self] in self?.noticeHover.watchLeave() }
        sessionManager.onSessionsUpdated = { [weak self] in self?.refreshSessionToasts() }
        // Shown, hidden, moved, or resized: the notices follow, and start afresh when turned on.
        floatingIndicator.onFrameChanged = { [weak self] in self?.refreshSessionToasts() }
        // The floating indicator controls its notices, as the menu bar dots control the panel: a
        // click pins them, and resting the pointer on it shows them until the pointer leaves both.
        floatingIndicator.onClick = { [weak self] in self?.sessionToasts.toggle() }
        floatingIndicator.onViewCreated = { [weak self] view in self?.noticeHover.track(view) }
        noticeHover.restDelay = 0
        noticeHover.anchors = { [weak self] in [self?.floatingIndicator.visibleFrame].compactMap { $0 } }
        noticeHover.keepOpenZones = { [weak self] in
            [self?.floatingIndicator.visibleFrame, self?.sessionToasts.visibleFrame].compactMap { $0 }
        }
        noticeHover.isPeeking = { [weak self] in self?.sessionToasts.visibility.peeking == true }
        noticeHover.onRest = { [weak self] in
            self?.sessionToasts.setPeeking(true)
            self?.noticeHover.watchLeave()
        }
        noticeHover.onLeave = { [weak self] in self?.sessionToasts.setPeeking(false) }
    }

    @MainActor private func refreshSessionToasts() {
        sessionToasts.update(sessionManager.sessionToastCandidates())
    }

    @MainActor private func openSessionToast(_ id: String) {
        guard let target = sessionManager.focusTarget(forCctopSessionID: id) else { return }
        focusTerminal(session: target)
    }
}
