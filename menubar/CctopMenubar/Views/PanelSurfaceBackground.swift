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

/// The theme color laid evenly over the glass. One even layer keeps the panel a single surface;
/// the glass draws its own rim.
enum PanelGlassTint {
    static let opacity: CGFloat = 0.6
}

struct PanelSurfaceBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        switch PanelSurfaceStyle.resolve(
            reduceTransparency: reduceTransparency,
            liquidGlassAvailable: PanelSurfaceStyle.liquidGlassAvailable
        ) {
        case .solid:
            Color.panelBackground
        case .liquidGlass:
            ZStack {
                liquidGlass
                tint
            }
        case .blur:
            ZStack {
                BehindWindowBlur()
                tint
            }
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppChrome.panelCornerRadius, style: .continuous)
    }

    @ViewBuilder private var liquidGlass: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        }
    }

    private var tint: some View {
        Color.panelBackground.opacity(PanelGlassTint.opacity)
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
