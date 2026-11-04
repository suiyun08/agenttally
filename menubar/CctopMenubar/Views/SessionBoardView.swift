import SwiftUI

/// How the Active tab lays out its sessions.
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

/// The board's columns, left to right in the Active tab's own order.
enum SessionBoardColumnKind: CaseIterable, Hashable {
    case waiting
    case working
    case finished
    case background

    init(status: SessionStatus) {
        switch status {
        case .waitingPermission, .waitingInput, .needsAttention: self = .waiting
        case .working, .compacting: self = .working
        // Idle sessions belong to the Idle tab; a stale row lands with the finished ones.
        case .done, .idle: self = .finished
        case .background: self = .background
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .waiting: return "board.waiting"
        case .working: return "board.working"
        case .finished: return "board.finished"
        case .background: return "board.background"
        }
    }

    var dotColor: Color {
        switch self {
        case .waiting: return Color.statusAttention
        case .working: return Color.statusGreen
        case .finished: return Color.accentColor
        case .background: return Color.statusIdle
        }
    }
}

enum SessionBoardMetrics {
    static let columnWidth: CGFloat = 260
    static let columnSpacing: CGFloat = 8
    static let horizontalPadding: CGFloat = 10
    static let cardSpacing: CGFloat = 6
    static let columnTitleHeight: CGFloat = 20
    /// Lines a collapsed card shows.
    static let recentEntryCount = 5
    /// The top bar and tab row above the board, and the padding below it.
    static let panelChromeHeight: CGFloat = 96
    static let expanderHeight: CGFloat = 14
    static let timelineVerticalPadding: CGFloat = 7
    /// What an expanded card's timeline takes besides its scrolling lines.
    static let timelineChromeHeight: CGFloat = expanderHeight + 4 + 2 * timelineVerticalPadding
    /// An expanded card keeps this much room for its lines even in a crowded column.
    static let minExpandedTimelineHeight: CGFloat = 140

    /// The panel width for all columns, never narrower than the list's width or wider than `maxWidth`.
    static func width(maxWidth: CGFloat) -> CGFloat {
        let count = CGFloat(SessionBoardColumnKind.allCases.count)
        let content = count * columnWidth + (count - 1) * columnSpacing + 2 * horizontalPadding
        return min(max(content, CGFloat(PanelWidth.current.rawValue)), maxWidth)
    }

    /// Room for a column's cards: the panel's height limit less everything above and below them.
    static func cardsHeight(panelMaxHeight: CGFloat) -> CGFloat {
        max(minExpandedTimelineHeight, panelMaxHeight - panelChromeHeight - columnTitleHeight - cardSpacing)
    }

    /// The height each expanded card's lines scroll in. Expanded cards share what the column's
    /// other cards and their own headers leave, so no card is pushed out of the column.
    static func expandedTimelineHeight(
        cardsHeight: CGFloat, fixedHeight: CGFloat, expandedCount: Int, cardCount: Int
    ) -> CGFloat {
        let spacing = CGFloat(max(cardCount - 1, 0)) * cardSpacing
        let share = (cardsHeight - fixedHeight - spacing) / CGFloat(max(expandedCount, 1))
        return max(minExpandedTimelineHeight, share - timelineChromeHeight)
    }
}

/// The Active tab as four status columns, one card per session.
struct SessionBoardView<Header: View>: View {
    typealias Identity = SessionIdentityPolicy.LogicalIdentity

    let rows: [PanelSessionRow]
    @ObservedObject var timelines: SessionTimelineStore
    let selectedIdentity: Identity?
    let maxHeight: CGFloat
    @Binding var expanded: Set<Identity>
    var onLayoutChanged: () -> Void = {}
    @ViewBuilder let header: (PanelSessionRow) -> Header

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: SessionBoardMetrics.columnSpacing) {
                    ForEach(SessionBoardColumnKind.allCases, id: \.self) { kind in
                        SessionBoardColumn(
                            kind: kind,
                            rows: rows.filter { SessionBoardColumnKind(status: $0.session.status) == kind },
                            timelines: timelines,
                            selectedIdentity: selectedIdentity,
                            cardsHeight: SessionBoardMetrics.cardsHeight(panelMaxHeight: maxHeight),
                            expanded: $expanded,
                            onLayoutChanged: onLayoutChanged,
                            header: header
                        )
                        .id(kind)
                    }
                }
                .padding(.horizontal, SessionBoardMetrics.horizontalPadding)
                .padding(.bottom, AppChrome.listVerticalPadding + 6)
            }
            .onChange(of: selectedIdentity) { identity in
                // On a screen too narrow for every column, bring the selected card's column in.
                guard let row = rows.first(where: { $0.id == identity }) else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(SessionBoardColumnKind(status: row.session.status), anchor: .center)
                }
            }
        }
        .onAppear { timelines.refresh(rows.map(\.session)) }
        .onChange(of: refreshKey) { _ in
            timelines.refresh(rows.map(\.session))
            // A session that left the tab forgets that it was expanded.
            let shown = Set(rows.map(\.id))
            if !expanded.isSubset(of: shown) { expanded.formIntersection(shown) }
        }
        .onChange(of: expanded) { _ in onLayoutChanged() }
        .onReceive(timelines.$states) { _ in onLayoutChanged() }
    }

    /// Changes whenever a shown session records new activity, so its transcript is read again.
    private var refreshKey: [String] {
        rows.map { "\($0.session.id)|\($0.session.lastActivity.timeIntervalSince1970)|\($0.session.status.rawValue)" }
    }
}

/// One status column: its title, then its sessions' cards top to bottom.
struct SessionBoardColumn<Header: View>: View {
    typealias Identity = SessionIdentityPolicy.LogicalIdentity

    let kind: SessionBoardColumnKind
    let rows: [PanelSessionRow]
    @ObservedObject var timelines: SessionTimelineStore
    let selectedIdentity: Identity?
    let cardsHeight: CGFloat
    @Binding var expanded: Set<Identity>
    let onLayoutChanged: () -> Void
    let header: (PanelSessionRow) -> Header
    @State private var cardHeights: SessionBoardHeights = [:]
    @State private var headerHeights: SessionBoardHeights = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: SessionBoardMetrics.cardSpacing) {
            title
            if rows.isEmpty {
                Text("No sessions")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textMuted)
                    .padding(.horizontal, 6)
            } else {
                cards
            }
        }
        .frame(width: SessionBoardMetrics.columnWidth, alignment: .topLeading)
        .onPreferenceChange(SessionBoardCardHeightKey.self) { heights in
            cardHeights = heights
            onLayoutChanged()
        }
        .onPreferenceChange(SessionBoardHeaderHeightKey.self) { headerHeights = $0 }
    }

    private var title: some View {
        HStack(spacing: 5) {
            Circle().fill(kind.dotColor).frame(width: 6, height: 6)
            Text(kind.title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
            Text(verbatim: "\(rows.count)")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.textMuted)
        }
        .padding(.horizontal, 6)
        .frame(height: SessionBoardMetrics.columnTitleHeight)
    }

    private var cards: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: SessionBoardMetrics.cardSpacing) {
                    ForEach(rows) { row in
                        card(row).id(row.id)
                    }
                }
            }
            // Hug the cards; past the screen's room the column scrolls.
            .frame(height: cardsContentHeight.map { min($0, cardsHeight) })
            .frame(maxHeight: cardsHeight)
            .onChange(of: selectedIdentity) { identity in
                guard let identity, rows.contains(where: { $0.id == identity }) else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(identity, anchor: .center)
                }
            }
        }
    }

    private func card(_ row: PanelSessionRow) -> some View {
        let isExpanded = expanded.contains(row.id)
        return SessionBoardCard(
            id: row.id,
            state: timelines.state(for: row.session),
            isExpanded: isExpanded,
            expandedTimelineHeight: isExpanded ? expandedTimelineHeight : 0,
            onToggle: {
                if isExpanded { expanded.remove(row.id) } else { expanded.insert(row.id) }
            },
            header: { header(row) }
        )
    }

    private var cardsContentHeight: CGFloat? {
        let heights = rows.compactMap { cardHeights[$0.id] }
        guard heights.count == rows.count else { return nil }
        return heights.reduce(0, +) + CGFloat(rows.count - 1) * SessionBoardMetrics.cardSpacing
    }

    private var expandedTimelineHeight: CGFloat {
        let fixed = rows.reduce(CGFloat(0)) { sum, row in
            // An expanded card's lines take the share; only its header counts as fixed.
            let height = expanded.contains(row.id) ? headerHeights[row.id] : cardHeights[row.id]
            return sum + (height ?? 0)
        }
        return SessionBoardMetrics.expandedTimelineHeight(
            cardsHeight: cardsHeight,
            fixedHeight: fixed,
            expandedCount: rows.filter { expanded.contains($0.id) }.count,
            cardCount: rows.count
        )
    }
}

/// A session's card: the list's session card on top (a click jumps to the session), its latest
/// lines below.
struct SessionBoardCard<Header: View>: View {
    let id: SessionIdentityPolicy.LogicalIdentity
    let state: TimelineState
    let isExpanded: Bool
    let expandedTimelineHeight: CGFloat
    let onToggle: () -> Void
    @ViewBuilder let header: () -> Header

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                header().padding(.top, 2)
                Rectangle()
                    .fill(Color.cardBorder)
                    .frame(height: 0.5)
                    .padding(.horizontal, 10)
            }
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: SessionBoardHeaderHeightKey.self, value: [id: geometry.size.height])
                }
            }
            SessionBoardTimeline(
                state: state,
                isExpanded: isExpanded,
                expandedHeight: expandedTimelineHeight,
                onToggle: onToggle
            )
        }
        .background {
            RoundedRectangle(cornerRadius: AppChrome.selectionCornerRadius, style: .continuous)
                .fill(Color.cardBackground.opacity(0.55))
        }
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: SessionBoardCardHeightKey.self, value: [id: geometry.size.height])
            }
        }
    }
}

/// A card's lines: the latest few, or every line scrolling in a bounded box when expanded.
struct SessionBoardTimeline: View {
    let state: TimelineState
    let isExpanded: Bool
    let expandedHeight: CGFloat
    let onToggle: () -> Void
    @State private var contentHeight: CGFloat?

    var body: some View {
        switch state {
        case .loading:
            note("Reading history…")
        case .unavailable:
            note("No conversation history")
        case .entries(let entries) where entries.isEmpty:
            note("No rounds yet")
        case .entries(let entries):
            VStack(alignment: .leading, spacing: 4) {
                let hidden = entries.count - SessionBoardMetrics.recentEntryCount
                if hidden > 0 { expander(hidden: hidden) }
                if isExpanded && hidden > 0 {
                    scrollingLines(entries)
                } else {
                    lines(Array(entries.suffix(SessionBoardMetrics.recentEntryCount)))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, SessionBoardMetrics.timelineVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func expander(hidden: Int) -> some View {
        Button(action: onToggle) {
            HStack(spacing: 3) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 8, weight: .semibold))
                Text(isExpanded ? LocalizedStringKey("Show less") : LocalizedStringKey("board.earlier \(hidden)"))
                    .font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(Color.accentColor)
            .frame(height: SessionBoardMetrics.expanderHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func lines(_ entries: [TimelineEntry]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(entries) { entry in
                TimelineEntryRow(entry: entry).id(entry.id)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Every line, opened at the newest, in a box no taller than `expandedHeight`.
    private func scrollingLines(_ entries: [TimelineEntry]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                lines(entries)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(key: SessionBoardContentHeightKey.self, value: geometry.size.height)
                        }
                    }
            }
            .frame(height: min(contentHeight ?? expandedHeight, expandedHeight))
            .onPreferenceChange(SessionBoardContentHeightKey.self) { contentHeight = $0 }
            .onAppear {
                // Wait for the box to take its height before opening it at the newest line.
                guard let last = entries.last?.id else { return }
                DispatchQueue.main.async { proxy.scrollTo(last, anchor: .bottom) }
            }
            .onChange(of: entries.last?.id) { last in
                guard let last else { return }
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(last, anchor: .bottom) }
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

typealias SessionBoardHeights = [SessionIdentityPolicy.LogicalIdentity: CGFloat]

/// Each card's full height, keyed by session.
struct SessionBoardCardHeightKey: PreferenceKey {
    static let defaultValue: SessionBoardHeights = [:]

    static func reduce(value: inout SessionBoardHeights, nextValue: () -> SessionBoardHeights) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Each card's session header height, keyed by session.
struct SessionBoardHeaderHeightKey: PreferenceKey {
    static let defaultValue: SessionBoardHeights = [:]

    static func reduce(value: inout SessionBoardHeights, nextValue: () -> SessionBoardHeights) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct SessionBoardContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
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
