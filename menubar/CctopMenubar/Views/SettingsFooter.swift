import AppKit
import SwiftUI

/// The end of Settings: quitting cctop, then the version and the project it is built on.
struct SettingsFooter: View {
    private static let upstreamURL = URL(string: "https://github.com/st0012/cctop")
    @State private var linkHovered = false

    var body: some View {
        VStack(spacing: 10) {
            QuitRow()
            footnote
        }
        .padding(.top, 12)
    }

    /// The upstream credit stays: cctop's MIT license asks for it.
    private var footnote: some View {
        HStack(spacing: 4) {
            Text(verbatim: "cctop v\(Bundle.main.appVersion)")
            Text(verbatim: "\u{00B7}")
            Text("Based on")
            Button {
                if let url = Self.upstreamURL { NSWorkspace.shared.open(url) }
            } label: {
                Text(verbatim: "st0012/cctop")
                    .foregroundStyle(linkHovered ? Color.textPrimary : Color.textSecondary)
                    .underline(linkHovered)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .onHover { linkHovered = $0 }
            Text(verbatim: "\u{00B7} MIT")
        }
        .font(.system(size: 10))
        .foregroundStyle(Color.textMuted)
        .lineLimit(1)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }
}

/// Quits cctop from a settings row. Never the keyboard focus: with focus rings hidden,
/// Space would quit unseen.
private struct QuitRow: View {
    @State private var isHovered = false

    var body: some View {
        Button { NSApplication.shared.terminate(nil) } label: {
            HStack(spacing: 8) {
                Text("Quit cctop")
                Spacer(minLength: 8)
                Image(systemName: "power")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(isHovered ? Color.textPrimary : Color.textSecondary)
            .padding(.horizontal, AppChrome.settingsRowHorizontalPadding)
            .frame(maxWidth: .infinity, minHeight: 28)
            .background(isHovered ? Color.panelSelectionBackground : Color.groupedRowBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppChrome.groupCornerRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}
