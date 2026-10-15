import Combine
import SwiftUI

private let pageAnimationDuration: TimeInterval = 0.18
private let relativeTimeRefresh = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

struct PopupView: View {
    let userSessions: [UserSession]
    var recentProjects: [RecentProject] = []
    var recentResumeTargets: [RecentResumeTarget]?
    var cleanupCandidates: [WorktreeCleanupCandidate] = []
    var cleanupIsScanning = false
    var cleanupHasUnseenCandidates = false
    @ObservedObject var updater: UpdaterBase
    let pluginManager: PluginManager
    var navigate: NavigateController?
    @ObservedObject var overlayController: OverlayController = OverlayController()
    var initialTab: PopupTab = .active
    var initialCleanupCandidate: WorktreeCleanupCandidate?
    var onOpenUpdater: (() -> Void)?
    var onHideSession: (SessionIdentityPolicy.LogicalIdentity) -> Void = { _ in }
    var onSelectCleanupRemovalAction: ((WorktreeCleanupCandidate) async -> WorktreeRemovalService.RemovalAction)?
    var onExecuteCleanupRemovalAction: ((WorktreeRemovalService.RemovalAction) async -> WorktreeRemovalService.RemovalResult)?
    var onCleanupTabVisible: () -> Void = {}
    var onCleanupTabHidden: () -> Void = {}
    /// Called (async on main) whenever content layout changes so the host can resize the panel.
    var onLayoutChanged: () -> Void = {}
    /// Upper bound for scrolling lists. The panel host passes its screen-based limit.
    var maxListHeight: CGFloat = AppChrome.overlayMinimumContentHeight
    @State var selectedTab: PopupTab = .active
    @State var selectedIndex: Int?
    @State var selectedSessionIdentity: SessionIdentityPolicy.LogicalIdentity?
    @State var selectedCleanupCandidate: WorktreeCleanupCandidate?
    @State var cleanupRemovalNotice: WorktreeRemovalNotice?
    @State var removingCleanupCandidateID: String?
    @State var pendingConfirmation: PopupConfirmation?
    @State var cleanupRemovalSelectsCandidateOnResult = true
    @State private var ocBannerInstalled = false
    @State private var lastFocusTime: Date = .distantPast
    @State private var piBannerInstalled = false
    @State var relativeTimeNow = Date()
    @AppStorage("ocBannerDismissed") private var ocBannerDismissed = false
    @AppStorage("piBannerDismissed") private var piBannerDismissed = false

    private var showOcBanner: Bool {
        pluginManager.ocConfigExists && !pluginManager.ocInstalled && !ocBannerDismissed
    }
    private var showPiBanner: Bool {
        pluginManager.piConfigExists && !pluginManager.piInstalled && !piBannerDismissed
    }

    private var showTabs: Bool { availableTabs.count > 1 && overlayController.active == nil }
    private var currentPage: PanelPage { overlayController.active == .settings ? .settings : .sessions }

    /// The top bar and, on the session page, the tabs: they float over the page.
    private var topChrome: some View {
        VStack(spacing: 0) {
            PanelTopBar(
                counts: StatusCounts(userSessions: userSessions),
                page: currentPage,
                hasUpdate: updater.pendingUpdateVersion != nil,
                onSelect: selectPage
            )
            if showTabs {
                tabPicker
            }
        }
    }

    private var pageContent: some View {
        ZStack(alignment: .top) {
            if currentPage == .settings {
                SettingsSection(
                    updater: updater,
                    pluginManager: pluginManager,
                    onOpenUpdater: onOpenUpdater,
                    maxHeight: maxListHeight
                )
                .transition(.opacity)
            } else {
                Group {
                    switch selectedTab {
                    case .active: activeContent
                    case .idle: idleContent
                    case .recent: recentContent
                    case .cleanup: cleanupContent
                    }
                }
                .frame(maxWidth: .infinity)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: pageAnimationDuration), value: overlayController.active)
    }

    var body: some View {
        pageContent
            .modifier(FloatingTopChrome(chrome: topChrome))
        .onReceive(navigate?.didActivateSubject.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()) { _ in
            selectedIndex = nil
            selectedSessionIdentity = nil
            if selectedTab != .active { selectedTab = .active }
            if overlayController.active != nil { closeOverlay() }
        }
        .onReceive(navigate?.navActionSubject.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()) { action in
            guard overlayController.active == nil else { return }
            handleNavAction(action)
        }
        .onReceive(relativeTimeRefresh) { relativeTimeNow = $0 }
        .onChange(of: selectedTab) { handleSelectedTabChanged($0) }
        .onChange(of: recentTargets.map(\.id)) { _ in ensureSelectedTabAvailable() }
        .onChange(of: actionableCleanupCandidates) { _ in handleCleanupCandidatesChanged() }
        .onChange(of: cleanupIsScanning) { _ in handleCleanupScanningChanged() }
        .onChange(of: selectedCleanupCandidate?.id) { _ in notifyLayoutChanged() }
        .alert(item: $pendingConfirmation) { confirmationAlert(for: $0) }
        .onAppear {
            selectedTab = availableTabs.contains(initialTab) ? initialTab : .active
            if selectedTab == .cleanup,
               let initialCleanupCandidate,
               actionableCleanupCandidates.contains(where: { $0.id == initialCleanupCandidate.id }) {
                selectedCleanupCandidate = initialCleanupCandidate
            }
            if selectedTab == .cleanup {
                onCleanupTabVisible()
            } else {
                onCleanupTabHidden()
            }
        }
    }

    // MARK: - Tab picker

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(availableTabs, id: \.self) { tab in
                tabButton(
                    tab.label,
                    count: count(for: tab),
                    tab: tab,
                    isScanning: tab == .cleanup && cleanupIsScanning,
                    hasAttention: tab == .cleanup && cleanupHasUnseenCandidates
                )
            }
        }
        .padding(2)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func count(for tab: PopupTab) -> Int {
        switch tab {
        case .active: return activeSessionRows.count
        case .idle: return idleSessionRows.count
        case .recent: return recentTargets.count
        case .cleanup: return actionableCleanupCandidates.count
        }
    }

    private func tabButton(
        _ label: String,
        count: Int,
        tab: PopupTab,
        isScanning: Bool = false,
        hasAttention: Bool = false
    ) -> some View {
        TabButtonView(
            label: label,
            count: count,
            isScanning: isScanning,
            hasAttention: hasAttention && selectedTab != tab,
            isSelected: selectedTab == tab
        ) {
            if overlayController.active != nil { closeOverlay() }
            withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tab }
            notifyLayoutChanged()
        }
        .help(tab.helpText)
    }
    // MARK: - Active tab
    private var activeContent: some View {
        Group {
            if userSessions.isEmpty {
                EmptyStateView(pluginManager: pluginManager)
            } else if activeSessionRows.isEmpty {
                noActiveSessionsContent
            } else {
                VStack(spacing: 0) {
                    if showOcBanner {
                        ToolInstallBanner(
                            toolName: "opencode", iconLabel: ">_", iconColor: Color.opencodeBadge,
                            installAction: { pluginManager.installOpenCodePlugin() },
                            installed: $ocBannerInstalled, dismissed: $ocBannerDismissed)
                    }
                    if showPiBanner {
                        ToolInstallBanner(
                            toolName: "pi", iconLabel: "\u{03C0}", iconColor: Color.piBadge,
                            installAction: { pluginManager.installPiPlugin() },
                            installed: $piBannerInstalled, dismissed: $piBannerDismissed)
                    }
                    sessionList(activeSessionRows, tab: .active, showNavigateNumbers: true)
                }
            }
        }
    }
    // MARK: - Idle tab
    @ViewBuilder
    private var idleContent: some View {
        if idleSessionRows.isEmpty {
            noIdleSessionsContent
        } else {
            sessionList(idleSessionRows, tab: .idle)
        }
    }
    func panelList<Item: Identifiable, Row: View>(
        _ list: [Item],
        tab: PopupTab,
        @ViewBuilder row: @escaping (Int, Item, Bool) -> Row
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, item in
                        row(index, item, selectedIndex == index)
                            .id(item.id)
                    }
                }
                .padding(.bottom, AppChrome.listVerticalPadding)
            }
            .frame(maxHeight: maxListHeight)
            .onChange(of: selectedIndex) { newIndex in
                guard selectedTab == tab,
                      let idx = newIndex, idx < list.count else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(list[idx].id, anchor: .center)
                }
            }
        }
    }
}

// MARK: - Pages

extension PopupView {
    var actionableCleanupCandidates: [WorktreeCleanupCandidate] {
        cleanupCandidates.filter(\.state.isActionable)
    }
    private func syncSelectedCleanupCandidate() {
        selectedCleanupCandidate = Self.syncedCleanupCandidate(
            selectedCleanupCandidate,
            in: actionableCleanupCandidates
        )
    }
    private var availableTabs: [PopupTab] {
        PopupTab.allCases
    }

    func focusSession(_ session: SessionData) {
        guard Date().timeIntervalSince(lastFocusTime) > 0.5 else { return }
        lastFocusTime = Date()
        focusTerminal(session: session)
    }

    /// The top bar's buttons: each shows its page; picking the page already shown does nothing.
    func selectPage(_ page: PanelPage) {
        switch page {
        case .settings:
            guard overlayController.active != .settings else { return }
            pluginManager.refresh()
            overlayController.active = .settings
            notifyLayoutChanged()
        case .sessions:
            closeOverlay()
        }
    }
    private func closeOverlay() {
        guard overlayController.active != nil else { return }
        overlayController.active = nil
        notifyLayoutChanged()
    }

    func notifyLayoutChanged() {
        DispatchQueue.main.async { onLayoutChanged() }
    }
    private func handleNavAction(_ action: PanelNavAction) {
        switch action {
        case .up: moveSelection(by: -1)
        case .down: moveSelection(by: 1)
        case .confirm: confirmSelection()
        case .escape, .reset:
            selectedIndex = nil
            selectedSessionIdentity = nil
        case .toggleTab, .previousTab, .nextTab: switchTab(to: action)
        }
    }

    private func moveSelection(by delta: Int) {
        switch selectedTab {
        case .active:
            moveSessionSelection(by: delta, in: activeSessionRows)
            return
        case .idle:
            moveSessionSelection(by: delta, in: idleSessionRows)
            return
        case .recent:
            moveIndexedSelection(by: delta, count: recentTargets.count)
        case .cleanup:
            moveIndexedSelection(by: delta, count: actionableCleanupCandidates.count)
        }
    }

    private func moveIndexedSelection(by delta: Int, count: Int) {
        guard count > 0 else { return }
        selectedIndex = selectedIndex.map { ($0 + delta + count) % count } ?? (delta > 0 ? 0 : count - 1)
    }

    private func confirmSelection() {
        if selectedTab == .active || selectedTab == .idle {
            confirmSessionSelection()
            return
        }
        guard let index = selectedIndex else { return }
        guard let target = PopupSelectionTarget.target(
            for: selectedTab,
            index: index,
            in: PopupSelectionContext(
                recentProjects: recentProjects,
                recentResumeTargets: recentTargets,
                cleanupCandidates: actionableCleanupCandidates
            )
        ) else {
            return
        }
        switch target {
        case .recentTarget(let target):
            openRecentResumeTarget(target)
            NSApp.deactivate()
        case .cleanupCandidate(let candidate):
            openCleanupDetail(candidate)
        }
        if isNavigateActive && target.confirmsNavigate {
            navigate?.didConfirmSubject.send()
        }
    }

    private func switchTab(to action: PanelNavAction) {
        guard showTabs else { return }
        let tabs = availableTabs
        let newTab = PopupTab.switched(from: selectedTab, action: action, availableTabs: tabs)
        guard newTab != selectedTab else { return }
        if overlayController.active != nil { closeOverlay() }
        withAnimation(.easeInOut(duration: 0.15)) { selectedTab = newTab }
        notifyLayoutChanged()
    }

    private func ensureSelectedTabAvailable() {
        guard availableTabs.contains(selectedTab) else {
            selectedTab = .active
            return
        }
        syncSelectedCleanupCandidate()
    }

    func handleCleanupCandidatesChanged() {
        ensureSelectedTabAvailable()
        syncSelectedCleanupCandidate()
        cleanupRemovalNotice = Self.noticeAfterCleanupCandidatesChanged(cleanupRemovalNotice)
        notifyLayoutChanged()
    }

    func openCleanupDetail(_ candidate: WorktreeCleanupCandidate) {
        cleanupRemovalNotice = nil
        selectedCleanupCandidate = candidate
    }
}
