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
    static let defaultTransparency = 0.75

    static func opacity(transparency: Double) -> Double {
        1 - min(max(transparency, 0), 1)
    }
}

/// The panel's own backdrop: just the theme tint. The glass lives in `PanelGlassWindow` below the
/// panel, so it keeps one look whether or not the panel holds keyboard focus.
struct PanelSurfaceBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(PanelGlassTint.transparencyKey) private var transparency = PanelGlassTint.defaultTransparency

    var body: some View {
        if reduceTransparency {
            Color.panelBackground
        } else {
            Color.panelBackground.opacity(PanelGlassTint.opacity(transparency: transparency))
        }
    }
}

/// The glass itself, filling `PanelGlassWindow`.
struct PanelGlassBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        switch PanelSurfaceStyle.resolve(
            reduceTransparency: reduceTransparency,
            liquidGlassAvailable: PanelSurfaceStyle.liquidGlassAvailable
        ) {
        case .solid:
            Color.clear
        case .liquidGlass:
            liquidGlass
        case .blur:
            BehindWindowBlur()
                .clipShape(shape)
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppChrome.panelCornerRadius, style: .continuous)
    }

    @ViewBuilder private var liquidGlass: some View {
        if #available(macOS 26.0, *) {
            // Clear glass: far less frosting than .regular, so what is behind the panel shows.
            Color.clear.glassEffect(.clear, in: shape)
        }
    }
}

/// What sits behind the panel window, blurred; the pre-macOS 26 stand-in for Liquid Glass.
private struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Holds the panel's glass in a window of its own, attached right below the panel. macOS draws
/// glass in a key window with a brighter active look and in any other window with a quieter
/// inactive look; this window never becomes key, so the glass never switches as the panel
/// gains and loses focus. It takes no clicks, and the panel keeps it on its frame.
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
