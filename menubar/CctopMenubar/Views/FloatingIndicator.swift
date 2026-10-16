import AppKit
import SwiftUI

/// Where the floating indicator sits: a top-right default under the menu bar, always wholly on a
/// screen, and growing or shrinking from the edge nearest the screen's side.
enum FloatingIndicatorPlacement {
    /// A press that moves less than this is a click, not a drag.
    static let dragThreshold: CGFloat = 3
    static let margin: CGFloat = 12

    static func isDrag(from start: NSPoint, to end: NSPoint) -> Bool {
        hypot(end.x - start.x, end.y - start.y) >= dragThreshold
    }

    static func defaultFrame(size: NSSize, visible: NSRect) -> NSRect {
        NSRect(
            x: visible.maxX - size.width - margin, y: visible.maxY - size.height - margin,
            width: size.width, height: size.height
        )
    }

    static func kept(_ frame: NSRect, within visible: NSRect) -> NSRect {
        var kept = frame
        kept.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        kept.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        return kept
    }

    /// The frame at a new size, keeping its top and the side nearest the screen's edge, so
    /// the indicator grows away from the edge it was put against.
    static func resized(_ frame: NSRect, to size: NSSize, within visible: NSRect) -> NSRect {
        let keepsRight = frame.midX > visible.midX
        let originX = keepsRight ? frame.maxX - size.width : frame.minX
        let resized = NSRect(x: originX, y: frame.maxY - size.height, width: size.width, height: size.height)
        return kept(resized, within: visible)
    }

    /// The saved top-left corner, if it still lands on one of the screens.
    static func restored(originX: CGFloat, topY: CGFloat, size: NSSize, visibleFrames: [NSRect]) -> NSRect? {
        let frame = NSRect(x: originX, y: topY - size.height, width: size.width, height: size.height)
        guard let visible = visibleFrames.first(where: { $0.contains(NSPoint(x: frame.midX, y: frame.midY)) }) else {
            return nil
        }
        return kept(frame, within: visible)
    }
}

/// What the floating indicator shows.
final class FloatingIndicatorModel: ObservableObject {
    @Published var counts = StatusCounts.zero
}

/// The floating indicator: the menu bar's dots on a small glass capsule.
struct FloatingIndicatorView: View {
    @ObservedObject var model: FloatingIndicatorModel
    /// Off when the window wraps the view in `SystemGlass` instead.
    var drawsGlass = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    static let height: CGFloat = 26
    private static let padding: CGFloat = 9
    private static let emptyLine = NSSize(width: 16, height: 3)

    static func size(for counts: StatusCounts) -> NSSize {
        let content = counts.dotGroups.isEmpty
            ? emptyLine.width
            : StatusDotLayout(groups: counts.dotGroups, metrics: .floating).width
        return NSSize(width: ceil(content + padding * 2), height: height)
    }

    var body: some View {
        Group {
            if model.counts.dotGroups.isEmpty {
                Capsule().fill(Color.primary.opacity(0.5))
                    .frame(width: Self.emptyLine.width, height: Self.emptyLine.height)
            } else {
                StatusDotsView(
                    layout: StatusDotLayout(groups: model.counts.dotGroups, metrics: .floating),
                    metrics: .floating,
                    palette: .adaptive,
                    height: StatusDotMetrics.floating.markHeight
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(CapsuleGlass(enabled: drawsGlass, reduceTransparency: reduceTransparency))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.counts.accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }
}

/// Regular, interactive Liquid Glass on macOS 26, as on the system's own small buttons: it turns
/// dark over dark content and light over light, letting what is behind show through. Its window
/// never becomes key, and glass in an inactive window is drawn thicker, so the active state is
/// pinned as in the panel. The behind-window blur before macOS 26, and the theme's solid color
/// when the user reduces transparency.
private struct CapsuleGlass: ViewModifier {
    let enabled: Bool
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        if !enabled {
            content
        } else if reduceTransparency {
            content.background(Color.panelBackground, in: Capsule())
        } else if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: Capsule())
                .environment(\.controlActiveState, .key)
        } else {
            content.background(BehindWindowBlur().clipShape(Capsule()))
        }
    }
}

/// The floating indicator's window: on every desktop and over full-screen apps, never taking
/// keyboard focus. A click opens the panel; a drag moves the indicator.
final class FloatingIndicatorWindow: NSPanel {
    var onClick: (() -> Void)?
    var onMoved: ((NSRect) -> Void)?

    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        // The glass draws its own depth; a window shadow would make the capsule look solid.
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        ignoresMouseEvents = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        guard event.type == .leftMouseDown else { return super.sendEvent(event) }
        trackPress()
    }

    private func trackPress() {
        let start = NSEvent.mouseLocation
        let startOrigin = frame.origin
        var dragged = false
        while let event = nextEvent(
            matching: [.leftMouseDragged, .leftMouseUp], until: .distantFuture, inMode: .eventTracking, dequeue: true
        ), event.type != .leftMouseUp {
            let location = NSEvent.mouseLocation
            guard dragged || FloatingIndicatorPlacement.isDrag(from: start, to: location) else { continue }
            dragged = true
            var moved = frame
            moved.origin = NSPoint(x: startOrigin.x + location.x - start.x, y: startOrigin.y + location.y - start.y)
            let visible = NSScreen.screens.first(where: { $0.frame.contains(location) })?.visibleFrame
                ?? screen?.visibleFrame
            setFrameOrigin(visible.map { FloatingIndicatorPlacement.kept(moved, within: $0) }?.origin ?? moved.origin)
        }
        if dragged {
            onMoved?(frame)
        } else {
            onClick?()
        }
    }
}

/// Shows the floating indicator while Settings › General › Floating Indicator is on, keeps it in
/// step with the menu bar's dots, and remembers where the user put it.
@MainActor
final class FloatingIndicatorController {
    static let enabledKey = "floatingIndicatorEnabled"
    private static let originXKey = "floatingIndicatorOriginX"
    private static let topYKey = "floatingIndicatorTopY"

    var onClick: () -> Void = {}
    /// Called with the indicator's view once it exists, for hover tracking.
    var onViewCreated: (NSView) -> Void = { _ in }

    private let model = FloatingIndicatorModel()
    private var window: FloatingIndicatorWindow?
    private var observers: [NSObjectProtocol] = []

    init() {
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncVisibility() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.fit() }
        })
    }

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// The indicator's screen frame while it shows.
    var visibleFrame: NSRect? {
        guard let window, window.isVisible else { return nil }
        return window.frame
    }

    func update(_ counts: StatusCounts) {
        guard counts != model.counts else { return }
        model.counts = counts
        fit()
    }

    /// Shows or hides the indicator with its setting, in the light or dark mode chosen in Settings.
    func syncVisibility() {
        window?.appearance = AppearanceMode.current.appearance
        if Self.isEnabled {
            show()
        } else {
            window?.orderOut(nil)
        }
    }

    private func show() {
        let window = self.window ?? makeWindow()
        fit()
        if !window.isVisible { window.orderFrontRegardless() }
    }

    private func makeWindow() -> FloatingIndicatorWindow {
        let window = FloatingIndicatorWindow()
        window.appearance = AppearanceMode.current.appearance
        let host = NSHostingView(rootView: FloatingIndicatorView(model: model, drawsGlass: !SystemGlass.isAvailable))
        host.sizingOptions = []
        window.contentView = SystemGlass.wrapping(host, cornerRadius: FloatingIndicatorView.height / 2)
        window.onClick = { [weak self] in self?.onClick() }
        window.onMoved = { frame in
            UserDefaults.standard.set(frame.minX, forKey: Self.originXKey)
            UserDefaults.standard.set(frame.maxY, forKey: Self.topYKey)
        }
        window.setFrame(initialFrame(size: FloatingIndicatorView.size(for: model.counts)), display: false)
        self.window = window
        onViewCreated(host)
        return window
    }

    private func initialFrame(size: NSSize) -> NSRect {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.originXKey) != nil, defaults.object(forKey: Self.topYKey) != nil,
           let restored = FloatingIndicatorPlacement.restored(
               originX: defaults.double(forKey: Self.originXKey), topY: defaults.double(forKey: Self.topYKey),
               size: size, visibleFrames: NSScreen.screens.map(\.visibleFrame)
           ) {
            return restored
        }
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        return FloatingIndicatorPlacement.defaultFrame(size: size, visible: visible)
    }

    /// Sizes the indicator to its dots and keeps it on a screen.
    private func fit() {
        guard let window else { return }
        let size = FloatingIndicatorView.size(for: model.counts)
        guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        let fitted = FloatingIndicatorPlacement.resized(window.frame, to: size, within: visible)
        if fitted != window.frame { window.setFrame(fitted, display: true) }
    }
}
