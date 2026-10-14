import KeyboardShortcuts
import SwiftUI

struct SettingsSecondaryRow<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color.groupedRowBorder)
                .frame(height: 0.5)
            HStack(spacing: spacing) {
                content
            }
            .padding(.horizontal, AppChrome.settingsRowHorizontalPadding)
            .padding(.vertical, 4)
            .frame(minHeight: 25)
        }
    }
}

struct StatusDotBadge: View {
    let text: LocalizedStringKey

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Color.statusGreen).frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(Color.textMuted)
        }
    }
}

struct InstalledBadge: View { var body: some View { StatusDotBadge(text: "Installed") } }

/// The muted "Remove" text button shared by the plugin rows.
struct PluginRemoveButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text("Remove")
                .font(.system(size: 10))
                .foregroundStyle(isHovered ? Color.textPrimary : Color.textMuted)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

struct AmberSegmentedPicker<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: AppChrome.settingsSegmentSpacing) {
            ForEach(options.indices, id: \.self) { index in
                SegmentButton(
                    label: options[index].label,
                    isSelected: selection == options[index].value
                ) {
                    withAnimation(.easeOut(duration: 0.15)) { selection = options[index].value }
                }
            }
        }
        .padding(AppChrome.settingsSegmentedControlPadding)
        .frame(height: AppChrome.settingsSegmentedControlHeight)
        .background(Color.segmentBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppChrome.settingsSegmentedControlCornerRadius, style: .continuous))
    }
}

private struct SegmentButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .allowsTightening(true)
                .padding(.horizontal, AppChrome.settingsSegmentHorizontalPadding)
                .frame(height: AppChrome.settingsSegmentHeight)
                .foregroundStyle(foregroundColor)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: AppChrome.settingsSegmentSelectionCornerRadius, style: .continuous)
                            .fill(Color.segmentThumbBackground)
                            .shadow(color: Color.black.opacity(0.18), radius: 1, y: 1)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: AppChrome.settingsSegmentSelectionCornerRadius, style: .continuous)
                            .fill(Color.panelSelectionBackground.opacity(0.62))
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: AppChrome.settingsSegmentSelectionCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var foregroundColor: Color {
        if isSelected { return Color.segmentActiveText }
        if isHovered { return Color.segmentActiveText.opacity(0.7) }
        return Color.segmentText
    }
}

struct ShortcutBadge: View {
    let name: KeyboardShortcuts.Name
    @State private var showRecorder = false
    @State private var isHovered = false

    var body: some View {
        Button { showRecorder.toggle() } label: {
            if let shortcut = KeyboardShortcuts.getShortcut(for: name) {
                Text(shortcut.description)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(isHovered ? Color.segmentActiveText : Color.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isHovered ? Color.panelSelectionBackground : Color.textPrimary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                Text("Record Shortcut")
                    .font(.system(size: 10))
                    .foregroundStyle(isHovered ? Color.textPrimary : Color.textMuted)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .popover(isPresented: $showRecorder) {
            KeyboardShortcuts.Recorder("", name: name)
                .padding(8)
        }
    }
}

/// Language picker for the Appearance group. The choice takes effect after a relaunch.
struct LanguageSettingsRow: View {
    @State private var selection = AppLanguage.current(in: .standard)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Language")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                AmberSegmentedPicker(
                    options: AppLanguage.allCases.map { ($0, $0.label) },
                    selection: $selection
                )
            }
            .padding(.horizontal, AppChrome.settingsRowHorizontalPadding)
            .padding(.vertical, 4)
            .frame(minHeight: 25)
            if selection != AppLanguage.launchSelection {
                SettingsSecondaryRow {
                    Text("Restart cctop to apply the language")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textMuted)
                    Spacer()
                    AmberActionButton(label: "Restart Now") { AppLanguage.relaunchApp() }
                }
            }
        }
        .onChange(of: selection) { $0.apply() }
    }
}

/// Panel width picker for the Appearance group.
struct PanelWidthSettingsRow: View {
    @AppStorage(PanelWidth.defaultsKey) private var width = PanelWidth.standard.rawValue

    var body: some View {
        HStack(spacing: 8) {
            Text("Panel Width")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            AmberSegmentedPicker(
                options: PanelWidth.allCases.map { ($0.rawValue, $0.label) },
                selection: $width
            )
        }
        .padding(.horizontal, AppChrome.settingsRowHorizontalPadding)
        .padding(.vertical, 4)
        .frame(minHeight: 25)
    }
}

/// The Appearance group's language and panel width rows, each under a divider.
struct LanguageAndWidthSettingsRows: View {
    var body: some View {
        VStack(spacing: 0) {
            divider
            LanguageSettingsRow()
            divider
            PanelWidthSettingsRow()
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.groupedRowBorder)
            .frame(height: 0.5)
            .padding(.leading, AppChrome.settingsDividerLeadingPadding)
    }
}

