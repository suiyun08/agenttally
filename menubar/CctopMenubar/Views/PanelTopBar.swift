import SwiftUI

/// The panel's two pages, one per top-bar button.
enum PanelPage: Equatable {
    case sessions
    case settings
}

/// The floating bar over the panel: the status lights with the app name stand for the session
/// list, the gear for settings. The current page's button carries a faint fill, kept quiet so it
/// never competes with the session status colors.
struct PanelTopBar: View {
    let counts: StatusCounts
    let page: PanelPage
    let onSelect: (PanelPage) -> Void

    var body: some View {
        HStack(spacing: 8) {
            PanelChromeButton(isSelected: page == .sessions, action: { onSelect(.sessions) }) {
                HStack(spacing: 7) {
                    PanelStatusLights(counts: counts)
                    Text(verbatim: "cctop")
                        .font(.system(size: 12.5, weight: .semibold))
                        .tracking(-0.1)
                }
                .padding(.horizontal, 11)
            }
            .accessibilityLabel(counts.accessibilityLabel)
            Spacer(minLength: 8)
            PanelChromeButton(isSelected: page == .settings, action: { onSelect(.settings) }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 28)
            }
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .frame(height: AppChrome.headerHeight)
    }
}

/// A capsule button on the top bar: Liquid Glass on macOS 26, a faint capsule before it.
struct PanelChromeButton<Label: View>: View {
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            label()
                .frame(height: 28)
                .foregroundStyle(isSelected ? Color.textPrimary : Color.textSecondary)
                .background {
                    Capsule(style: .continuous)
                        .fill(Color.panelSelectionBackground.opacity(isSelected ? 1 : (isHovered ? 0.5 : 0)))
                }
                .modifier(ChromeButtonSurface())
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: PanelHeaderControlFramesKey.self,
                    value: [proxy.frame(in: .named(PanelHeaderControlFramesKey.coordinateSpace))]
                )
            }
        }
    }
}

private struct ChromeButtonSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
        } else {
            content
                .background(Capsule(style: .continuous).fill(Color.panelControlBackground))
                .overlay(Capsule(style: .continuous).stroke(Color.panelControlBorder, lineWidth: 0.5))
        }
    }
}

/// The same per-agent status lights as the menu bar item; a short line when nothing needs a look.
struct PanelStatusLights: View {
    let counts: StatusCounts
    private static let maxWidth: CGFloat = 170

    var body: some View {
        if counts.dotGroups.isEmpty {
            Capsule()
                .fill(Color.textMuted)
                .frame(width: 14, height: 3)
        } else {
            let metrics = StatusDotMetrics.menubar
            let layout = StatusDotLayout(groups: counts.dotGroups, metrics: metrics, maxWidth: Self.maxWidth)
            ZStack(alignment: .leading) {
                ForEach(Array(layout.items.enumerated()), id: \.offset) { _, item in
                    switch item {
                    case .dot(let dot, let xPos):
                        light(dot)
                            .frame(width: metrics.dotDiameter, height: metrics.dotDiameter)
                            .offset(x: xPos)
                    case .separator(let xPos):
                        Rectangle()
                            .fill(Color.textMuted.opacity(0.6))
                            .frame(width: metrics.separatorWidth, height: 10)
                            .offset(x: xPos)
                    case .overflow(let text, let xPos, let width):
                        Text(verbatim: text)
                            .font(Font(metrics.overflowFont as CTFont))
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize()
                            .frame(width: width, alignment: .leading)
                            .offset(x: xPos)
                    }
                }
            }
            .frame(width: layout.width, height: 12, alignment: .leading)
        }
    }

    @ViewBuilder
    private func light(_ dot: StatusDotGroup.Dot) -> some View {
        switch dot {
        case .unreadDone:
            Circle().strokeBorder(Color.accentColor, lineWidth: 1.2)
        case .permission:
            Circle().fill(Color.statusPermission)
        case .attention:
            Circle().fill(Color.statusAttention)
        case .working:
            Circle().fill(Color.statusGreen)
        }
    }
}

/// Frames of the top bar's buttons in the panel's coordinate space, so the panel can leave clicks
/// on them to the buttons and drag the panel from the rest of the bar.
struct PanelHeaderControlFramesKey: PreferenceKey {
    static let coordinateSpace = "panelContent"
    static let defaultValue: [CGRect] = []

    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

/// Floats the top bar over a page: the page scrolls beneath it and fades out under it.
struct FloatingTopChrome<Chrome: View>: ViewModifier {
    let chrome: Chrome

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .safeAreaBar(edge: .top, spacing: 0) { chrome }
                .scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content.safeAreaInset(edge: .top, spacing: 0) {
                chrome.background(alignment: .top) {
                    LinearGradient(
                        colors: [Color.panelBackground.opacity(0.92), Color.panelBackground.opacity(0)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .padding(.bottom, -12)
                }
            }
        }
    }
}
