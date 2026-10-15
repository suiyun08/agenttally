import Foundation

/// Source classification for session badge rendering.
/// Drives source badge rendering in `SessionCardView` and `SourceBadgeView`.
enum AgentBadge: Hashable {
    case cc            // Claude Code CLI
    case claudeDesktop // Claude Desktop app
    case codex
    case opencode
    case pi
    case dsh           // DeepSeek Harness
    /// An agent cctop has no mark for, known by the harness name its plugin reports.
    case other(String)

    /// The short user-facing source label.
    var label: String {
        switch self {
        case .cc: return "CC"
        case .claudeDesktop: return "Claude Desktop"
        case .codex: return "Codex"
        case .opencode: return "OC"
        case .pi: return "Pi"
        case .dsh: return "DSH"
        case .other(let name): return name
        }
    }

    /// The agent's full name, for tooltips and spoken labels beside its mark.
    var fullName: String {
        switch self {
        case .cc: return "Claude Code"
        case .claudeDesktop: return "Claude Desktop"
        case .codex: return "Codex"
        case .opencode: return "opencode"
        case .pi: return "pi"
        case .dsh: return "DSH"
        case .other(let name): return name
        }
    }

    /// Desktop variants keep their full app label and desktop-specific layout behavior.
    var isDesktop: Bool {
        switch self {
        case .claudeDesktop: return true
        default: return false
        }
    }
}

extension SessionData {
    /// Classify the session source. Codex is one source across every surface.
    ///
    var agentBadge: AgentBadge {
        if isCodex { return .codex }
        if trustedHostApp == .claudeDesktop { return .claudeDesktop }
        switch source {
        case nil, SessionData.ccSource: return .cc
        case SessionData.opencodeSource: return .opencode
        case SessionData.piSource: return .pi
        case SessionData.dshSource: return .dsh
        case let name?: return name.isEmpty ? .cc : .other(name)
        }
    }
}
