import SwiftUI

/// How the Active and Idle tabs lay out their sessions.
enum SessionLayout: String {
    case list
    case board

    static let defaultsKey = "sessionLayout"
}

/// The width the panel takes while the board shows, reported up to the panel host.
struct PanelBoardWidthKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
    }
}

enum SessionBoardMetrics {
    static let columnWidth: CGFloat = 260
    static let columnSpacing: CGFloat = 8
    static let horizontalPadding: CGFloat = 10
    /// Room the top bar, tabs and session card take above a column's timeline.
    static let chromeHeight: CGFloat = 150

    /// The panel width for `columns` columns, never narrower than the list's width or wider than `maxWidth`.
    static func width(columns: Int, maxWidth: CGFloat) -> CGFloat {
        let count = CGFloat(max(columns, 1))
        let content = count * columnWidth + (count - 1) * columnSpacing + 2 * horizontalPadding
        return min(max(content, CGFloat(PanelWidth.current.rawValue)), maxWidth)
    }
}

/// One column per session: the session card on top, its rounds of conversation below.
struct SessionBoardView<Header: View>: View {
    let rows: [PanelSessionRow]
    @ObservedObject var timelines: SessionTimelineStore
    let selectedIdentity: SessionIdentityPolicy.LogicalIdentity?
    let maxHeight: CGFloat
    @ViewBuilder let header: (PanelSessionRow) -> Header

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: SessionBoardMetrics.columnSpacing) {
                    ForEach(rows) { row in
                        column(row).id(row.id)
                    }
                }
                .padding(.horizontal, SessionBoardMetrics.horizontalPadding)
                .padding(.bottom, AppChrome.listVerticalPadding + 6)
            }
            .onChange(of: selectedIdentity) { identity in
                guard let identity else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(identity, anchor: .center)
                }
            }
        }
        .onAppear { timelines.refresh(rows.map(\.session)) }
        .onChange(of: refreshKey) { _ in timelines.refresh(rows.map(\.session)) }
    }

    /// Changes whenever a shown session records new activity, so its transcript is read again.
    private var refreshKey: [String] {
        rows.map { "\($0.session.id)|\($0.session.lastActivity.timeIntervalSince1970)|\($0.session.status.rawValue)" }
    }

    private func column(_ row: PanelSessionRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(row)
                .padding(.top, 2)
            Rectangle()
                .fill(Color.cardBorder)
                .frame(height: 0.5)
                .padding(.horizontal, 10)
            SessionTimelineColumn(
                state: timelines.state(for: row.session),
                maxHeight: max(120, maxHeight - SessionBoardMetrics.chromeHeight)
            )
        }
        .frame(width: SessionBoardMetrics.columnWidth, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: AppChrome.selectionCornerRadius, style: .continuous)
                .fill(Color.cardBackground.opacity(0.55))
        }
    }
}

/// A session's rounds, oldest first, opened at the newest.
struct SessionTimelineColumn: View {
    let state: TimelineState
    let maxHeight: CGFloat

    var body: some View {
        switch state {
        case .loading:
            note("Reading history…")
        case .unavailable:
            note("No conversation history")
        case .entries(let entries) where entries.isEmpty:
            note("No rounds yet")
        case .entries(let entries):
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(entries) { entry in
                            TimelineEntryRow(entry: entry).id(entry.id)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: maxHeight)
                .onAppear {
                    if let last = entries.last?.id { proxy.scrollTo(last, anchor: .bottom) }
                }
                .onChange(of: entries.last?.id) { last in
                    guard let last else { return }
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Color.textMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TimelineEntryRow: View {
    let entry: TimelineEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(entry.role == .user ? LocalizedStringKey("timeline.you") : LocalizedStringKey("timeline.agent"))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(entry.role == .user ? Color.textMuted : Color.amber)
                .frame(width: 28, alignment: .leading)
            Text(entry.text)
                .font(.system(size: 11.5))
                .foregroundStyle(entry.role == .user ? Color.textSecondary : Color.textPrimary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The list / board switch at the end of the tab row.
struct SessionLayoutToggle: View {
    @Binding var layout: SessionLayout

    var body: some View {
        HStack(spacing: 0) {
            button(.list, symbol: "list.bullet", help: "List")
            button(.board, symbol: "rectangle.split.3x1", help: "Board")
        }
        .padding(2)
        .background {
            Capsule(style: .continuous).fill(Color.panelSelectionBackground.opacity(0.35))
        }
    }

    private func button(_ value: SessionLayout, symbol: String, help: LocalizedStringKey) -> some View {
        Button {
            layout = value
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(layout == value ? Color.textPrimary : Color.textMuted)
                .frame(width: 24, height: 18)
                .background {
                    if layout == value {
                        Capsule(style: .continuous).fill(Color.panelSelectionBackground)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(Text(help))
    }
}
