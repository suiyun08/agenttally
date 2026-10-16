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
}

/// The panel's own backdrop. Under Liquid Glass the tint rides on the glass (see `PanelLiquidGlass`);
/// before macOS 26 it lies over the blur in `PanelGlassWindow`.
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

/// Regular Liquid Glass behind the panel's content, in the panel's own window. Glass and text
/// share a window, so the system adapts both to what is behind the panel and keeps the text
/// readable. The active state is pinned, so the glass keeps one look whether or not the panel
/// holds keyboard focus. The transparency setting only thins the theme tint on it: regular glass
/// has no transparency of its own to set.
struct PanelLiquidGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(PanelGlassTint.transparencyKey) private var transparency = PanelGlassTint.defaultTransparency

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !reduceTransparency {
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

/// Holds the panel's blur in a window of its own, attached right below the panel, before macOS 26.
/// It never becomes key, so the blur never switches look as the panel gains and loses focus. It
/// takes no clicks, and the panel keeps it on its frame. On macOS 26 the glass is drawn in the
/// panel itself (see `PanelLiquidGlass`) and this window stays detached.
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
        let host = NSHostingView(rootView: PanelGlassBackdrop())
        host.sizingOptions = []
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
