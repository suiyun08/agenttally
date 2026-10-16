import AppKit
import SwiftUI

enum AppChrome {
    static let cornerRadius: CGFloat = 8
    static let headerHeight: CGFloat = 44
    static let rowSelectionHorizontalInset: CGFloat = 8
    static let panelCornerRadius: CGFloat = 16
    static let controlCornerRadius = cornerRadius
    static let selectionCornerRadius: CGFloat = 10
    static let groupCornerRadius = cornerRadius
    static let settingsContentPaddingHorizontal: CGFloat = 8
    static let settingsContentPaddingTop: CGFloat = 0
    static let settingsContentPaddingBottom: CGFloat = 6
    static let settingsRowHorizontalPadding: CGFloat = 10
    static let settingsSectionHeaderHorizontalPadding: CGFloat = 5
    static let settingsDividerLeadingPadding: CGFloat = 0
    static let settingsSegmentSpacing: CGFloat = 0
    static let settingsSegmentedControlPadding: CGFloat = 2
    static let settingsSegmentHorizontalPadding: CGFloat = 7
    static let settingsSegmentHeight: CGFloat = 17
    static let settingsSegmentedControlHeight = settingsSegmentHeight + settingsSegmentedControlPadding * 2
    static let settingsSegmentedControlCornerRadius: CGFloat = 7
    static let settingsSegmentSelectionCornerRadius: CGFloat = 5
    static let overlayMinimumContentHeight: CGFloat = 290
    static let settingsScrollViewportHeight: CGFloat = 454
    static let settingsContentPadding = EdgeInsets(
        top: settingsContentPaddingTop,
        leading: settingsContentPaddingHorizontal,
        bottom: settingsContentPaddingBottom,
        trailing: settingsContentPaddingHorizontal
    )
    static let listVerticalPadding: CGFloat = 4
}

extension Color {
    /// Accent color — the primary brand color, themed per color scheme.
    static var amber: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            ThemeManager.shared.current.accent.resolve(appearance)
        })
    }

    /// Segmented control background.
    static var segmentBackground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            ThemeManager.shared.current.segmentBackground.resolve(appearance)
        })
    }

    /// Native-style segmented-control selection thumb.
    static var segmentThumbBackground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            ThemeManager.shared.current.segmentThumbBackground.resolve(appearance)
        })
    }

    /// Segmented control inactive text.
    static var segmentText: Color { textSecondary }

    /// Active segment text.
    static var segmentActiveText: Color { textPrimary }

    /// Text shown on accent-filled action buttons.
    static var accentButtonText: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            ThemeManager.shared.current.accentButtonText.resolve(appearance)
        })
    }

    /// Settings section background.
    static var settingsBackground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            ThemeManager.shared.current.settingsBackground.resolve(appearance)
        })
    }

    /// Settings section border.
    static var settingsBorder: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            ThemeManager.shared.current.settingsBorder.resolve(appearance)
        })
    }

    /// Panel background.
    static var panelBackground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            ThemeManager.shared.current.panelBackground.resolve(appearance)
        })
    }

    /// Toolbar, tabs, footer, and small chrome controls.
    static var panelControlBackground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            ThemeManager.shared.current.panelControlBackground.resolve(appearance)
        })
    }

    /// Hairline border for panel chrome.
    static var panelControlBorder: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            ThemeManager.shared.current.panelControlBorder.resolve(appearance)
        })
    }

    /// Hairline used for selected surfaces and the panel rim.
    static var panelAccentBorder: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            ThemeManager.shared.current.panelAccentBorder.resolve(appearance)
        })
    }

    /// Rounded row and tab selection background.
    static var panelSelectionBackground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            ThemeManager.shared.current.panelSelectionBackground.resolve(appearance)
        })
    }

    /// Sunk background for secondary grouped views.
    static var groupedContentBackground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            ThemeManager.shared.current.groupedContentBackground.resolve(appearance)
        })
    }

    /// Grouped-list row background.
    static var groupedRowBackground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            ThemeManager.shared.current.groupedRowBackground.resolve(appearance)
        })
    }

    /// Grouped-list separator and border.
    static var groupedRowBorder: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            ThemeManager.shared.current.groupedRowBorder.resolve(appearance)
        })
    }

    /// Card background.
    static var cardBackground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            ThemeManager.shared.current.cardBackground.resolve(appearance)
        })
    }

    /// Card border.
    static var cardBorder: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            ThemeManager.shared.current.cardBorder.resolve(appearance)
        })
    }

    /// Attention/waiting status (less urgent than permission).
    static var statusAttention: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            ThemeManager.shared.current.statusAttention.resolve(appearance)
        })
    }

    /// Attention/waiting color adjusted for small text contrast.
    static var statusAttentionText: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            ThemeManager.shared.current.statusAttentionText.resolve(appearance)
        })
    }

    /// Permission status (urgent, needs approval).
    static var statusPermission: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            ThemeManager.shared.current.statusPermission.resolve(appearance)
        })
    }

    /// Permission color adjusted for small text contrast.
    static var statusPermissionText: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            ThemeManager.shared.current.statusPermissionText.resolve(appearance)
        })
    }

    /// Working status green.
    static var statusGreen: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            ThemeManager.shared.current.statusGreen.resolve(appearance)
        })
    }

    /// Working color adjusted for small text contrast.
    static var statusWorkingText: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            ThemeManager.shared.current.statusWorkingText.resolve(appearance)
        })
    }

    /// Idle status.
    static var statusIdle: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            ThemeManager.shared.current.statusIdle.resolve(appearance)
        })
    }

    // Text on glass is monochrome in three levels, as Apple's labels are, a little stronger than
    // the system's so it holds on translucent glass; theme color is kept for status and actions.

    /// Secondary text — project, branch, last message, setting descriptions.
    static var textSecondary: Color { Color(nsColor: .glassText(dark: 0.78, light: 0.62)) }

    /// Muted text — timestamps, section headers, unselected tabs, footer.
    static var textMuted: Color { Color(nsColor: .glassText(dark: 0.6, light: 0.48)) }

    /// Dimmed primary — idle project names.
    static var textDimmed: Color { textSecondary }

    /// Primary text.
    static var textPrimary: Color { Color(nsColor: .glassText(dark: 1, light: 0.88)) }

    /// Agent badge color.
    static var agentBadge: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            ThemeManager.shared.current.agentBadge.resolve(appearance)
        })
    }

    /// Source badge — opencode.
    static var opencodeBadge: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            ThemeManager.shared.current.opencodeBadge.resolve(appearance)
        })
    }

    /// Source badge — pi.
    static var piBadge: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            ThemeManager.shared.current.piBadge.resolve(appearance)
        })
    }

    /// Source badge — codex.
    static var codexBadge: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            ThemeManager.shared.current.codexBadge.resolve(appearance)
        })
    }

    /// Source badge — Claude Desktop.
    static var claudeDesktopBadge: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            ThemeManager.shared.current.claudeDesktopBadge.resolve(appearance)
        })
    }

}

private extension NSColor {
    /// White at `dark` opacity on dark glass, black at `light` opacity on light glass.
    static func glassText(dark: CGFloat, light: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1, alpha: dark) : NSColor(white: 0, alpha: light)
        }
    }
}
