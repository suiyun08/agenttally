import AppKit

/// The color to tint glass with in a given appearance; nil for none.
typealias GlassTint = @MainActor (NSAppearance) -> NSColor?

/// AppKit's Liquid Glass through two private settings of `NSGlassEffectView`: a variant beyond
/// the public regular and clear, and the subdued state macOS gives glass in an app that is not
/// frontmost. AgentTally is never frontmost, so with that state on its glass always looks flat
/// and frosted. Both settings are private and may change with macOS: when either is missing,
/// `make` returns nil and callers keep the public glass.
@MainActor
enum SystemGlass {
    /// Notification Center's glass: picked by eye as the closest to the system's own floating
    /// controls, clear with the bright rim and lensing at its edges.
    static let notificationCenter = 9

    private static let setters = ["set_variant:", "set_subduedState:"]

    /// Whether this macOS still has both private settings.
    static var isAvailable: Bool {
        guard #available(macOS 26.0, *) else { return false }
        return setters.allSatisfy { NSGlassEffectView.instancesRespond(to: NSSelectorFromString($0)) }
    }

    /// Glass of `variant` that keeps its full look while the app is in the background.
    @available(macOS 26.0, *)
    static func make(
        variant: Int = notificationCenter, cornerRadius: CGFloat, tint: GlassTint? = nil
    ) -> SteadyGlassEffectView? {
        guard isAvailable else { return nil }
        let glass = SteadyGlassEffectView(variant: variant)
        glass.cornerRadius = cornerRadius
        glass.tint = tint
        return glass
    }

    /// `content` embedded in the glass and pinned to its edges, or `content` alone without it.
    static func wrapping(
        _ content: NSView, cornerRadius: CGFloat, tint: GlassTint? = nil
    ) -> NSView {
        guard #available(macOS 26.0, *), let glass = make(cornerRadius: cornerRadius, tint: tint) else { return content }
        glass.contentView = content
        if !content.translatesAutoresizingMaskIntoConstraints {
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
                content.topAnchor.constraint(equalTo: glass.topAnchor),
                content.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
            ])
        } else {
            content.frame = glass.bounds
            content.autoresizingMask = [.width, .height]
        }
        return glass
    }
}

/// Glass that holds its private settings. AppKit sets the subdued state again whenever its
/// window gains or loses focus or the app comes and goes from the front, so this turns it back
/// off right after each of those. `tint` colors the glass for the appearance it is shown in.
@available(macOS 26.0, *)
final class SteadyGlassEffectView: NSGlassEffectView {
    var tint: GlassTint? {
        didSet { applyTint() }
    }

    private var observers: [NSObjectProtocol] = []

    init(variant: Int) {
        super.init(frame: .zero)
        setValue(variant, forKey: "_variant")
        holdFullLook()
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        guard let window else { return }
        let center = NotificationCenter.default
        let focusChanges: [(Notification.Name, AnyObject?)] = [
            (NSWindow.didBecomeKeyNotification, window), (NSWindow.didResignKeyNotification, window),
            (NSApplication.didBecomeActiveNotification, nil), (NSApplication.didResignActiveNotification, nil),
        ]
        for (name, object) in focusChanges {
            observers.append(center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.holdFullLookAfterAppKit() }
            })
        }
        // The tint follows the transparency setting and the theme, both kept in user defaults.
        observers.append(center.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyTint() }
        })
        holdFullLook()
        applyTint()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTint()
    }

    private func holdFullLook() {
        setValue(0, forKey: "_subduedState")
    }

    /// Now, and again once AppKit has finished reacting to the same change.
    private func holdFullLookAfterAppKit() {
        holdFullLook()
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.holdFullLook() }
        }
    }

    private func applyTint() {
        let color = tint?(effectiveAppearance)
        if tintColor != color { tintColor = color }
    }
}
