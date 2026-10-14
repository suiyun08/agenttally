import Foundation

struct HookInput: Codable {
    private static let codexProjectSuggestionPromptFragment =
        "Generate 0 to 3 hyperpersonalized suggestions"
    private static let codexSuggestionPromptFragmentOffset = 12

    let sessionId: String
    let cwd: String
    let transcriptPath: String?
    private let transcriptPathFieldPresent: Bool
    var permissionMode: String?
    let hookEventName: String
    var prompt: String?
    var toolName: String?
    var toolInput: [String: String]?
    var notificationType: String?
    var message: String?
    var title: String?
    var trigger: String?
    var error: String?
    /// Whether Stop was triggered by user interrupt (Ctrl+C). Reserved for future use:
    /// could distinguish idle (interrupted) from waitingInput (normal completion).
    var isInterrupt: Bool?
    var agentId: String?
    var agentType: String?
    var isSubagentSession: Bool?
    var source: String?
    var harnessName: String?
    var sessionName: String?
    /// Claude's final text for the turn (Stop), or the API error string (StopFailure).
    var lastAssistantMessage: String?
    var errorDetails: String?
    /// In-flight background work reported on Stop. Nil when the harness does not report it.
    var backgroundTasks: [HookBackgroundTask]?
    /// Number of scheduled wakeups (CronCreate, ScheduleWakeup, /loop) reported on Stop.
    var sessionCronCount: Int?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case cwd
        case transcriptPath = "transcript_path"
        case permissionMode = "permission_mode"
        case hookEventName = "hook_event_name"
        case prompt
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case notificationType = "notification_type"
        case message, title, trigger, error
        case isInterrupt = "is_interrupt"
        case agentId = "agent_id"
        case agentType = "agent_type"
        case isSubagentSession = "is_subagent"
        case source
        case harnessName = "harness_name"
        case sessionName = "session_name"
        case lastAssistantMessage = "last_assistant_message"
        case errorDetails = "error_details"
        case backgroundTasks = "background_tasks"
        case sessionCrons = "session_crons"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(cwd, forKey: .cwd)
        try container.encodeIfPresent(transcriptPath, forKey: .transcriptPath)
        try container.encodeIfPresent(permissionMode, forKey: .permissionMode)
        try container.encode(hookEventName, forKey: .hookEventName)
        try container.encodeIfPresent(prompt, forKey: .prompt)
        try container.encodeIfPresent(toolName, forKey: .toolName)
        try container.encodeIfPresent(toolInput, forKey: .toolInput)
        try container.encodeIfPresent(notificationType, forKey: .notificationType)
        try container.encodeIfPresent(message, forKey: .message)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(trigger, forKey: .trigger)
        try container.encodeIfPresent(error, forKey: .error)
        try container.encodeIfPresent(isInterrupt, forKey: .isInterrupt)
        try container.encodeIfPresent(agentId, forKey: .agentId)
        try container.encodeIfPresent(agentType, forKey: .agentType)
        try container.encodeIfPresent(isSubagentSession, forKey: .isSubagentSession)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encodeIfPresent(harnessName, forKey: .harnessName)
        try container.encodeIfPresent(sessionName, forKey: .sessionName)
        try container.encodeIfPresent(lastAssistantMessage, forKey: .lastAssistantMessage)
        try container.encodeIfPresent(errorDetails, forKey: .errorDetails)
        try container.encodeIfPresent(backgroundTasks, forKey: .backgroundTasks)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decode(String.self, forKey: .sessionId)
        cwd = try container.decode(String.self, forKey: .cwd)
        transcriptPathFieldPresent = container.contains(.transcriptPath)
        transcriptPath = try container.decodeIfPresent(String.self, forKey: .transcriptPath)
        permissionMode = try container.decodeIfPresent(String.self, forKey: .permissionMode)
        hookEventName = try container.decode(String.self, forKey: .hookEventName)
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt)
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        notificationType = try container.decodeIfPresent(String.self, forKey: .notificationType)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        trigger = try container.decodeIfPresent(String.self, forKey: .trigger)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        isInterrupt = try container.decodeIfPresent(Bool.self, forKey: .isInterrupt)
        agentId = try container.decodeIfPresent(String.self, forKey: .agentId)
        agentType = try container.decodeIfPresent(String.self, forKey: .agentType)
        isSubagentSession = try container.decodeIfPresent(Bool.self, forKey: .isSubagentSession)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        harnessName = try container.decodeIfPresent(String.self, forKey: .harnessName)
        sessionName = try container.decodeIfPresent(String.self, forKey: .sessionName)
        // Stop-time extras are advisory: a malformed value must never drop the whole event.
        lastAssistantMessage = try? container.decodeIfPresent(String.self, forKey: .lastAssistantMessage)
        errorDetails = try? container.decodeIfPresent(String.self, forKey: .errorDetails)
        backgroundTasks = try? container.decodeIfPresent([HookBackgroundTask].self, forKey: .backgroundTasks)
        sessionCronCount = (try? container.decodeIfPresent([IgnoredJSONValue].self, forKey: .sessionCrons))?.count

        if container.contains(.toolInput) {
            let rawDict = try? container.decode([String: ToolInputValue].self, forKey: .toolInput)
            toolInput = rawDict?.compactMapValues { $0.stringValue }
        } else {
            toolInput = nil
        }
    }

    /// Identifies which tool harness sent this event. Resolution order:
    ///   1. `harness_name` JSON field (set by plugins, or injected via `--harness` CLI arg)
    ///   2. `source` JSON field (legacy fallback — old opencode/pi plugins send this)
    ///
    /// The allowlist on the `source` fallback guards against Codex's `source` field,
    /// which carries the SessionStart trigger kind ("startup"/"resume"/"clear"), not a
    /// tool name.
    ///
    /// MIGRATION(harness_name): Remove the `source` fallback only after installer/status
    /// logic enforces plugins that send `harness_name`, or older-plugin compatibility is
    /// explicitly dropped. Installed opencode/pi plugins are not automatically overwritten.
    private static let knownHarnesses: Set<String> = ["cc", "codex", "opencode", "pi"]

    var resolvedHarnessName: String? {
        if let harnessName { return harnessName }
        // MIGRATION(harness_name): Legacy fallback for old plugins that send `source`.
        if let source, Self.knownHarnesses.contains(source) { return source }
        return nil
    }

    var transcriptPathWasExplicitlyNull: Bool {
        transcriptPathFieldPresent && transcriptPath == nil
    }

    /// Reads Codex's SessionStart kind from `trigger` or the legacy non-harness
    /// `source` field. Contradictory aliases intentionally fail open.
    var codexSessionStartKind: String? {
        let legacyKind: String?
        if let source, Self.knownHarnesses.contains(source) {
            guard harnessName == nil || harnessName == source else { return nil }
            legacyKind = nil
        } else {
            legacyKind = source
        }
        guard trigger == nil || legacyKind == nil || trigger == legacyKind else { return nil }
        return trigger ?? legacyKind
    }

    /// True when Stop reports work that will resume the session without the user.
    var hasBackgroundWork: Bool {
        !(backgroundTasks ?? []).isEmpty || (sessionCronCount ?? 0) > 0
    }

    var hasCodexStartupDeferralEvidence: Bool {
        resolvedHarnessName == SessionData.codexSource
            && codexSessionStartKind == "startup"
            && transcriptPathWasExplicitlyNull
    }

    var hasCodexProjectSuggestionEvidence: Bool {
        guard resolvedHarnessName == SessionData.codexSource,
              transcriptPathWasExplicitlyNull,
              let prompt,
              let range = prompt.range(of: Self.codexProjectSuggestionPromptFragment) else { return false }
        return prompt.distance(from: prompt.startIndex, to: range.lowerBound)
            == Self.codexSuggestionPromptFragmentOffset
    }
}

/// One in-flight task from Claude Code's Stop `background_tasks` array. Every field is optional
/// so new task types or missing fields still count the task.
struct HookBackgroundTask: Codable, Equatable {
    var type: String?
    var status: String?
    var description: String?
    var command: String?
    var name: String?
    var agentType: String?

    enum CodingKeys: String, CodingKey {
        case type, status, description, command, name
        case agentType = "agent_type"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try? container.decodeIfPresent(String.self, forKey: .type)
        status = try? container.decodeIfPresent(String.self, forKey: .status)
        description = try? container.decodeIfPresent(String.self, forKey: .description)
        command = try? container.decodeIfPresent(String.self, forKey: .command)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        agentType = try? container.decodeIfPresent(String.self, forKey: .agentType)
    }

    /// The most readable one-line label Claude Code supplied for this task.
    var displayDetail: String? {
        [description, command, name, agentType]
            .lazy
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

/// Accepts any JSON value; only the element count of the surrounding array is used.
private struct IgnoredJSONValue: Decodable {
    init(from decoder: Decoder) throws {}
}

private enum ToolInputValue: Decodable {
    case string(String)
    case other

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .other
        }
    }
}
