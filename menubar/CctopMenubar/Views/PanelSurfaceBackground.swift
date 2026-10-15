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

/// The theme color laid over the glass: mostly opaque behind the content so text stays crisp,
/// thinning toward the rim so the edges read as glass.
enum PanelGlassTint {
    static let centerOpacity: CGFloat = 0.75
    static let edgeOpacity: CGFloat = 0.3
    /// How far in from the rim the tint takes to reach its center strength.
    static let fadeWidth: CGFloat = 20

    /// The inner layer's opacity that, over the edge layer, adds up to the center opacity.
    static func innerOpacity(center: CGFloat = centerOpacity, edge: CGFloat = edgeOpacity) -> CGFloat {
        guard edge < 1 else { return 0 }
        return max(0, (center - edge) / (1 - edge))
    }
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
        ZStack {
            Color.panelBackground.opacity(PanelGlassTint.edgeOpacity)
            Color.panelBackground.opacity(PanelGlassTint.innerOpacity())
                .mask {
                    shape
                        .padding(PanelGlassTint.fadeWidth / 2)
                        .blur(radius: PanelGlassTint.fadeWidth / 2)
                }
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
