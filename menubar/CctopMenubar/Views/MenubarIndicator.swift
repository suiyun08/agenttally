import AppKit
import QuartzCore

/// The status item's picture plus the breathing fills of the dots that wait on the user.
///
/// The picture draws those dots as rings; one small layer per dot fades its fill in and out on
/// top. Core Animation runs the fades, so the menu bar is not redrawn many times a second, and
/// nothing runs when no dot is waiting or when macOS asks apps to reduce motion.
@MainActor
final class MenubarIndicator {
    private let button: NSButton
    private let fills = CALayer()
    private let reduceMotion: () -> Bool
    private var counts = StatusCounts.zero
    private var observers: [NSObjectProtocol] = []
    private var appearanceObservation: NSKeyValueObservation?

    init(
        button: NSButton,
        reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    ) {
        self.button = button
        self.reduceMotion = reduceMotion
        button.wantsLayer = true
        fills.zPosition = 1
        button.layer?.addSublayer(fills)
        button.postsFrameChangedNotifications = true
        observers.append(NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification, object: button, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layoutFills() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.redraw() }
        })
        // The menu bar turns light or dark with the wallpaper behind it; the fills follow.
        appearanceObservation = button.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.layoutFills() }
        }
    }

    /// How many dots are breathing now.
    var breathingDotCount: Int { fills.sublayers?.count ?? 0 }

    func show(_ counts: StatusCounts) {
        self.counts = counts
        redraw()
    }

    private func redraw() {
        button.image = MenubarIconRenderer.render(counts: counts, breathing: !reduceMotion())
        layoutFills()
    }

    private func layoutFills() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        fills.frame = button.bounds
        let spots = reduceMotion() ? [] : MenubarIconRenderer.breathingSpots(counts: counts)
        guard !spots.isEmpty, let image = button.image else {
            fills.sublayers = nil
            return
        }
        let imageRect = button.cell?.imageRect(forBounds: button.bounds) ?? NSRect(
            x: (button.bounds.width - image.size.width) / 2, y: (button.bounds.height - image.size.height) / 2,
            width: image.size.width, height: image.size.height
        )
        let appearance = button.effectiveAppearance
        let now = CACurrentMediaTime()
        fills.sublayers = spots.map { spot in
            let layer = CALayer()
            layer.frame = spot.rect.offsetBy(dx: imageRect.minX, dy: imageRect.minY)
            layer.cornerRadius = spot.rect.width / 2
            appearance.performAsCurrentDrawingAppearance {
                layer.backgroundColor = MenubarIconRenderer.color(for: spot.dot, appearance: appearance).cgColor
            }
            layer.add(DotBreathing.animation(phase: spot.phase, now: now), forKey: "breathing")
            return layer
        }
    }
}
