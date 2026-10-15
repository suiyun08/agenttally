import Foundation

// MARK: - Panel state types

/// Panel modes model the distinct behavioral states of the floating panel.
enum PanelMode: Equatable {
    case hidden
    case normal
    /// Opened by resting the pointer on the menu bar dots: shown without taking keyboard focus,
    /// and closed again once the pointer moves away. A click or drag pins it as `.normal`.
    case peek
    case navigate(origin: NavigateOrigin)
}

struct NavigateOrigin: Equatable {
    let panelWasClosed: Bool
}

struct PanelState: Equatable {
    var mode: PanelMode
}

// MARK: - Events & Actions

enum PanelEvent {
    case menubarIconClicked(
        appIsActive: Bool,
        onDifferentScreen: Bool = false,
        panelVisibleInActiveSpace: Bool = true
    )
    case escape
    case appLostFocus
    case navigateShortcut(panelVisibleInActiveSpace: Bool = true)
    case navigateConfirmed
    case navigateTimedOut
    case navKey(PanelNavAction)
    case unrecognizedKeyDuringNavigate
    /// The pointer rested on the menu bar dots (or the notch pill).
    case pointerRested(panelVisibleInActiveSpace: Bool = true)
    /// The pointer stayed off the dots and the panel for the whole grace period.
    case pointerLeft
    /// A mouse button went down inside the panel.
    case panelClicked
}

enum PanelAction: Equatable {
    case showPanel
    case peekPanel             // shows the panel without taking focus
    case dismissPanel          // hides panel + stops nav key monitor
    case positionPanel
    case activateApp
    case deactivateApp
    case startNavKeyMonitor
    case postNavAction(PanelNavAction)
    case activateExternalApp
    case restorePreviousApp
    case captureApps
    case startNavigateMode(panelWasClosed: Bool)
    case endNavigateMode
}

// MARK: - Pure coordinator

struct PanelCoordinator {
    struct Result: Equatable {
        let state: PanelState
        let actions: [PanelAction]
        let eventConsumed: Bool

        init(state: PanelState, actions: [PanelAction], eventConsumed: Bool = true) {
            self.state = state
            self.actions = actions
            self.eventConsumed = eventConsumed
        }
    }

    static func handle(event: PanelEvent, state: PanelState) -> Result {
        switch state.mode {
        case .hidden:
            return handleHidden(event: event, state: state)
        case .normal:
            return handleNormal(event: event, state: state)
        case .peek:
            return handlePeek(event: event, state: state)
        case .navigate(let origin):
            return handleNavigate(event: event, state: state, origin: origin)
        }
    }

    // MARK: - Per-mode handlers

    private static func handleHidden(event: PanelEvent, state: PanelState) -> Result {
        switch event {
        case .menubarIconClicked:
            return openPanelResult()
        case .navigateShortcut:
            return openPanelInNavigateModeResult()
        case .pointerRested:
            return peekResult()
        default:
            return Result(state: state, actions: [], eventConsumed: false)
        }
    }

    /// A click on the dots or the panel pins a peek instead of closing it, so the habit of
    /// clicking the dots never takes away the panel the pointer just opened.
    private static func handlePeek(event: PanelEvent, state: PanelState) -> Result {
        switch event {
        case .menubarIconClicked:
            return openPanelResult()
        case .panelClicked:
            return Result(state: PanelState(mode: .normal), actions: [.startNavKeyMonitor])
        case .pointerLeft:
            return Result(state: PanelState(mode: .hidden), actions: [.dismissPanel])
        case .navigateShortcut:
            return openPanelInNavigateModeResult()
        default:
            return Result(state: state, actions: [], eventConsumed: false)
        }
    }

    private static func handleNormal(event: PanelEvent, state: PanelState) -> Result {
        switch event {
        case .menubarIconClicked(appIsActive: _, onDifferentScreen: _, panelVisibleInActiveSpace: false):
            return openPanelResult()

        case .menubarIconClicked(appIsActive: _, onDifferentScreen: true, panelVisibleInActiveSpace: true):
            return Result(state: PanelState(mode: .normal), actions: [.positionPanel, .activateApp])

        case .menubarIconClicked(appIsActive: let appIsActive, onDifferentScreen: false, panelVisibleInActiveSpace: true):
            var actions: [PanelAction] = [.dismissPanel]
            if appIsActive { actions.append(.restorePreviousApp) }
            return Result(state: PanelState(mode: .hidden), actions: actions)

        case .escape:
            return Result(state: state, actions: [.postNavAction(.escape)])

        case .appLostFocus:
            return Result(state: state, actions: [])

        case .navigateShortcut(panelVisibleInActiveSpace: false):
            return openPanelInNavigateModeResult()

        case .navigateShortcut(panelVisibleInActiveSpace: true):
            let mode: PanelMode = .navigate(origin: NavigateOrigin(panelWasClosed: false))
            return Result(
                state: PanelState(mode: mode),
                actions: [.activateApp, .startNavigateMode(panelWasClosed: false)]
            )

        case .navKey(let action):
            return Result(state: state, actions: [.postNavAction(action)])

        case .pointerRested(panelVisibleInActiveSpace: false):
            return peekResult()

        default:
            return Result(state: state, actions: [], eventConsumed: false)
        }
    }

    private static func handleNavigate(event: PanelEvent, state: PanelState, origin: NavigateOrigin) -> Result {
        switch event {
        case .menubarIconClicked(appIsActive: _, onDifferentScreen: true, panelVisibleInActiveSpace: _):
            if !origin.panelWasClosed {
                return Result(
                    state: PanelState(mode: .normal),
                    actions: [.endNavigateMode, .positionPanel, .activateApp]
                )
            }
            return endNavigateResult(origin: origin, restoreFocus: false)

        case .menubarIconClicked, .escape, .navigateTimedOut, .unrecognizedKeyDuringNavigate:
            return endNavigateResult(origin: origin, restoreFocus: true)

        case .appLostFocus, .navigateConfirmed:
            return endNavigateResult(origin: origin, restoreFocus: false)

        case .navKey(let action):
            return Result(state: state, actions: [.postNavAction(action)])

        default:
            return Result(state: state, actions: [], eventConsumed: false)
        }
    }

    // MARK: - Helpers

    /// Show the panel in normal mode, remembering the apps to restore on dismiss.
    private static func openPanelResult() -> Result {
        Result(
            state: PanelState(mode: .normal),
            actions: [.captureApps, .showPanel, .activateApp, .startNavKeyMonitor, .postNavAction(.reset)]
        )
    }

    /// Show the panel as a peek, leaving keyboard focus with the app the user is in.
    private static func peekResult() -> Result {
        Result(state: PanelState(mode: .peek), actions: [.peekPanel, .postNavAction(.reset)])
    }

    /// Show a closed panel directly in navigate mode.
    private static func openPanelInNavigateModeResult() -> Result {
        Result(
            state: PanelState(mode: .navigate(origin: NavigateOrigin(panelWasClosed: true))),
            actions: [.showPanel, .activateApp, .startNavKeyMonitor, .startNavigateMode(panelWasClosed: true)]
        )
    }

    private static func endNavigateResult(origin: NavigateOrigin, restoreFocus: Bool) -> Result {
        var actions: [PanelAction] = [.endNavigateMode]
        if origin.panelWasClosed {
            actions.append(.dismissPanel)
        }
        actions.append(restoreFocus ? .activateExternalApp : .deactivateApp)
        return Result(
            state: PanelState(mode: origin.panelWasClosed ? .hidden : .normal),
            actions: actions
        )
    }
}
