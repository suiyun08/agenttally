import AppKit
import SwiftUI

/// How the panel's backdrop is drawn.
enum PanelSurfaceStyle: Equatable {
    /// macOS 26 Liquid Glass under the theme tint.
    case liquidGlass
    /// The classic behind-window blur under the theme tint, before macOS 26.
    case blur
    /// The theme's solid color, when the user has the system reduce transparency.
    case solid

    static func resolve(reduceTransparency: Bool, liquidGlassAvailable: Bool) -> PanelSurfaceStyle {
        if reduceTransparency { return .solid }
        return liquidGlassAvailable ? .liquidGlass : .blur
    }

    static var liquidGlassAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }
}

/// The theme color laid evenly over the glass, as strong as the user's transparency setting
/// leaves it. One even layer keeps the panel a single surface; the glass draws its own rim.
enum PanelGlassTint {
    /// How see-through the panel is, 0 (solid theme color) to 1 (bare glass).
    static let transparencyKey = "panelTransparency"
    /// Bare glass: the system's own look.
    static let defaultTransparency = 1.0

    static func opacity(transparency: Double) -> Double {
        1 - min(max(transparency, 0), 1)
    }

    /// The least tint on the panel's glass. The panel draws white text whatever is behind it, and
    /// this glass turns light over bright content, so — as Apple's guidance for translucent glass
    /// under light text asks — a dark layer of about 35% stays underneath. Over dark content it
    /// barely shows.
    static let dimmingFloor = 0.35

    /// The theme tint on the panel's `SystemGlass` in `appearance`: as strong as the transparency
    /// setting asks, and never below the dimming floor.
    @MainActor static func glassTint(for appearance: NSAppearance) -> NSColor? {
        let stored = UserDefaults.standard.object(forKey: transparencyKey) as? Double
        return glassTint(for: appearance, transparency: stored ?? defaultTransparency)
    }

    @MainActor static func glassTint(for appearance: NSAppearance, transparency: Double) -> NSColor? {
        let alpha = max(dimmingFloor, opacity(transparency: transparency))
        return ThemeManager.shared.current.panelBackground.resolve(appearance).withAlphaComponent(alpha)
    }
}

/// The panel's own backdrop. Under Liquid Glass the theme tint rides on the glass itself (see
/// `PanelGlassTint.glassTint` and `PanelLiquidGlass`); before macOS 26 it lies over the blur.
struct PanelSurfaceBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(PanelGlassTint.transparencyKey) private var transparency = PanelGlassTint.defaultTransparency

    var body: some View {
        switch PanelSurfaceStyle.resolve(
            reduceTransparency: reduceTransparency,
            liquidGlassAvailable: PanelSurfaceStyle.liquidGlassAvailable
        ) {
        case .solid:
            Color.panelBackground
        case .liquidGlass:
            Color.clear
        case .blur:
            Color.panelBackground.opacity(PanelGlassTint.opacity(transparency: transparency))
        }
    }
}

/// Regular Liquid Glass behind the panel's content, in the panel's own window: the fallback when
/// `SystemGlass` is unavailable. Glass and text
/// share a window, so the system adapts both to what is behind the panel and keeps the text
/// readable. The active state is pinned, so the glass keeps one look whether or not the panel
/// holds keyboard focus. The transparency setting only thins the theme tint on it: regular glass
/// has no transparency of its own to set.
struct PanelLiquidGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(PanelGlassTint.transparencyKey) private var transparency = PanelGlassTint.defaultTransparency

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !reduceTransparency, !SystemGlass.isAvailable {
            content
                .glassEffect(
                    .regular.tint(Color.panelBackground.opacity(PanelGlassTint.opacity(transparency: transparency))),
                    in: RoundedRectangle(cornerRadius: AppChrome.panelCornerRadius, style: .continuous)
                )
                .environment(\.controlActiveState, .key)
        } else {
            content
        }
    }
}

/// The blur before macOS 26, filling `PanelGlassWindow`.
struct PanelGlassBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            Color.clear
        } else {
            BehindWindowBlur()
                .clipShape(RoundedRectangle(cornerRadius: AppChrome.panelCornerRadius, style: .continuous))
        }
    }
}

/// What sits behind the panel window, blurred; the pre-macOS 26 stand-in for Liquid Glass.
struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Holds the panel's glass in a window of its own, attached right below the panel: Notification
/// Center's glass from `SystemGlass` on macOS 26, the blur before it. This window never becomes
/// key, so the glass keeps one look as the panel gains and loses focus. It takes no clicks, and
/// the panel keeps it on its frame. The panel's text is white, so it needs no adaptation from the
/// glass.
final class PanelGlassWindow: NSWindow {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        level = .floating
        collectionBehavior = FloatingPanel.defaultCollectionBehavior
        if #available(macOS 26.0, *), let glass = SystemGlass.make(
            cornerRadius: AppChrome.panelCornerRadius, tint: PanelGlassTint.glassTint(for:)
        ) {
            contentView = glass
        } else {
            let host = NSHostingView(rootView: PanelGlassBackdrop())
            host.sizingOptions = []
            contentView = host
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
