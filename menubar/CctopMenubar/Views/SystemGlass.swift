import AppKit

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
    static func make(variant: Int = notificationCenter, cornerRadius: CGFloat) -> NSGlassEffectView? {
        guard isAvailable else { return nil }
        let glass = NSGlassEffectView()
        glass.setValue(variant, forKey: "_variant")
        glass.setValue(0, forKey: "_subduedState")
        glass.cornerRadius = cornerRadius
        return glass
    }

    /// `content` embedded in the glass and pinned to its edges, or `content` alone without it.
    static func wrapping(_ content: NSView, cornerRadius: CGFloat) -> NSView {
        guard #available(macOS 26.0, *), let glass = make(cornerRadius: cornerRadius) else { return content }
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
