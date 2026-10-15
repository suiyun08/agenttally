import AppKit

/// Decides when a peek closes: once the pointer has stayed off the dots and the panel for the
/// whole grace period with no mouse button held. A held button is a drag in progress.
struct PeekLeaveTracker {
    let grace: TimeInterval
    private var outsideSince: Date?

    init(grace: TimeInterval) {
        self.grace = grace
    }

    mutating func shouldClose(pointerInside: Bool, buttonsPressed: Bool, now: Date) -> Bool {
        guard !pointerInside, !buttonsPressed else {
            outsideSince = nil
            return false
        }
        let since = outsideSince ?? now
        outsideSince = since
        return now.timeIntervalSince(since) >= grace
    }
}

/// Opens the panel as a peek when the pointer rests on the menu bar dots or the notch pill, and
/// closes a peek once the pointer has moved away from both the dots and the panel.
///
/// Resting takes a short pause, so sweeping the pointer along the menu bar opens nothing.
/// Leaving is checked by polling the pointer while a peek is open, not by exit events: a window
/// that appears under a still pointer gets no entered event, so its exit could never arrive.
@MainActor
final class PanelHoverController: NSResponder {
    static let enabledKey = "hoverOpensPanel"
    static let restDelay: TimeInterval = 0.25
    static let leaveGrace: TimeInterval = 0.5
    private static let pollInterval: TimeInterval = 0.1

    /// Screen frames the pointer rests on to open a peek: the dots and the notch pill.
    var anchors: () -> [NSRect] = { [] }
    /// Screen frames that keep a peek open: the anchors and the panel.
    var keepOpenZones: () -> [NSRect] = { [] }
    var isPeeking: () -> Bool = { false }
    var onRest: () -> Void = {}
    var onLeave: () -> Void = {}

    private var restTimer: Timer?
    private var leaveTimer: Timer?
    private var leaveTracker = PeekLeaveTracker(grace: PanelHoverController.leaveGrace)

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Watches the pointer entering and leaving `view`, an anchor.
    func track(_ view: NSView) {
        view.addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        restTimer?.invalidate()
        restTimer = scheduledTimer(after: Self.restDelay, repeats: false) { [weak self] in self?.restElapsed() }
    }

    override func mouseExited(with event: NSEvent) {
        restTimer?.invalidate()
        restTimer = nil
    }

    private func restElapsed() {
        restTimer = nil
        guard Self.isEnabled, NSEvent.pressedMouseButtons == 0,
              Self.contains(anchors(), NSEvent.mouseLocation) else { return }
        onRest()
    }

    /// Starts checking whether the pointer has left; it stops once the panel is no longer a peek.
    func watchLeave() {
        leaveTracker = PeekLeaveTracker(grace: Self.leaveGrace)
        guard leaveTimer == nil else { return }
        leaveTimer = scheduledTimer(after: Self.pollInterval, repeats: true) { [weak self] in self?.checkLeave() }
    }

    private func checkLeave() {
        guard isPeeking() else { return stopWatchingLeave() }
        let leaving = leaveTracker.shouldClose(
            pointerInside: Self.contains(keepOpenZones(), NSEvent.mouseLocation),
            buttonsPressed: NSEvent.pressedMouseButtons != 0,
            now: Date()
        )
        guard leaving else { return }
        stopWatchingLeave()
        onLeave()
    }

    private func stopWatchingLeave() {
        leaveTimer?.invalidate()
        leaveTimer = nil
    }

    private static func contains(_ zones: [NSRect], _ point: NSPoint) -> Bool {
        zones.contains { $0.contains(point) }
    }

    /// Fires on the main run loop in every mode, so drags and open menus don't hold it back.
    private func scheduledTimer(
        after interval: TimeInterval, repeats: Bool, _ action: @escaping @MainActor () -> Void
    ) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats) { _ in
            MainActor.assumeIsolated { action() }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
