import Foundation

enum SessionStatus: String, Codable {
    case idle
    case working
    case compacting
    case waitingPermission = "waiting_permission"
    case waitingInput = "waiting_input"
    case needsAttention = "needs_attention"
    /// The turn ended and nothing is in flight: the session is ready for the next prompt.
    case done
    /// Shown only: the user has read the finished turn, and background tasks it left will resume
    /// the session. Hooks record such a turn as `done`.
    case background

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SessionStatus(rawValue: raw) ?? (raw.contains("waiting") ? .needsAttention : .working)
    }

    var needsAttention: Bool {
        switch self {
        case .waitingPermission, .waitingInput, .needsAttention: return true
        default: return false
        }
    }

    var sortOrder: Int {
        switch self {
        case .waitingPermission: return 0
        case .waitingInput, .needsAttention: return 1
        case .working: return 2
        case .compacting: return 3
        case .done: return 4
        case .background: return 5
        case .idle: return 6
        }
    }

}
