import Foundation

enum HookEvent: Equatable {
    case sessionStart
    case userPromptSubmit
    case preToolUse
    /// PreToolUse or PermissionRequest for a tool that blocks on the user's answer
    /// (AskUserQuestion, ExitPlanMode). Claude Code sends both within a millisecond, in either
    /// order, so both must land on the same status.
    case awaitingUserAnswer
    case postToolUse
    case postToolUseFailure
    case stop
    /// Stop while background tasks or scheduled wakeups will resume the session.
    case stopWithBackgroundWork
    /// The turn ended on an API error (rate limit, authentication, billing, ...).
    case stopFailure
    case notificationIdle
    /// An MCP elicitation form is waiting for the user's input.
    case notificationElicitation
    case notificationPermission
    case notificationOther
    case permissionRequest
    case subagentStart
    case subagentStop
    case preCompact
    case postCompact
    case sessionError
    case sessionEnd
    case unknown

    private static let hookNameMap: [String: HookEvent] = [
        "SessionStart": .sessionStart, "UserPromptSubmit": .userPromptSubmit,
        "PreToolUse": .preToolUse, "PostToolUse": .postToolUse,
        "PostToolUseFailure": .postToolUseFailure, "Stop": .stop, "StopFailure": .stopFailure,
        "PermissionRequest": .permissionRequest, "PreCompact": .preCompact,
        "SubagentStart": .subagentStart, "SubagentStop": .subagentStop,
        "PostCompact": .postCompact, "SessionError": .sessionError,
        "SessionEnd": .sessionEnd,
    ]

    /// Tools whose PreToolUse means Claude is now waiting on the user's answer.
    static let awaitingUserToolNames: Set<String> = ["AskUserQuestion", "ExitPlanMode"]

    static func parse(
        hookName: String,
        notificationType: String?,
        toolName: String? = nil,
        hasBackgroundWork: Bool = false
    ) -> HookEvent {
        if hookName == "Notification" {
            switch notificationType {
            case "idle_prompt": return .notificationIdle
            case "elicitation_dialog", "elicitation_url_dialog": return .notificationElicitation
            case "permission_prompt": return .notificationPermission
            default: return .notificationOther
            }
        }
        let event = hookNameMap[hookName] ?? .unknown
        if event == .preToolUse || event == .permissionRequest,
           let toolName, awaitingUserToolNames.contains(toolName) {
            return .awaitingUserAnswer
        }
        if event == .stop, hasBackgroundWork {
            return .stopWithBackgroundWork
        }
        return event
    }

    /// Events that close a model turn, so they restart the "finished at" clock even when the
    /// status value itself does not change.
    var endsTurn: Bool {
        self == .stop || self == .stopWithBackgroundWork || self == .stopFailure
    }
}

enum Transition {
    /// Returns nil to mean "preserve current status".
    static func forEvent(_ current: SessionStatus, event: HookEvent) -> SessionStatus? {
        switch event {
        case .sessionStart, .postCompact: return .idle
        case .stop: return .done
        case .stopWithBackgroundWork: return .background
        case .stopFailure, .sessionError: return .needsAttention
        case .userPromptSubmit, .preToolUse, .postToolUse, .postToolUseFailure: return .working
        case .awaitingUserAnswer, .notificationElicitation: return .waitingInput
        // Claude Code sends idle_prompt about 60s after a turn ends. It never re-flags a finished
        // turn, but it still rescues a turn whose Stop never came (an Esc interrupt sends none).
        case .notificationIdle:
            return current == .working || current == .compacting ? .done : nil
        case .permissionRequest: return .waitingPermission
        case .preCompact: return .compacting
        // notificationPermission: PermissionRequest already sets waitingPermission immediately.
        // The Notification fires ~6s later and would race with PostToolUse if the user allows quickly.
        case .subagentStart, .subagentStop, .notificationPermission, .notificationOther, .sessionEnd, .unknown:
            return nil
        }
    }

    /// True when a hook is strong evidence that a previously ended/dormant session resumed.
    static func clearsInactiveMarkers(event: HookEvent) -> Bool {
        switch event {
        case .sessionStart, .userPromptSubmit, .preToolUse, .awaitingUserAnswer, .postToolUse,
             .postToolUseFailure, .stop, .stopWithBackgroundWork, .stopFailure, .notificationIdle,
             .notificationElicitation, .permissionRequest, .preCompact, .postCompact, .sessionError:
            return true
        case .notificationPermission, .notificationOther, .subagentStart, .subagentStop,
             .sessionEnd, .unknown:
            return false
        }
    }
}
