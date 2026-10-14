import SwiftUI

extension SessionStatus {
    var color: Color {
        switch self {
        case .waitingPermission: return Color.statusPermission
        case .waitingInput, .needsAttention: return Color.statusAttention
        case .working, .background: return Color.statusGreen
        case .compacting:
            return Color(nsColor: NSColor(name: nil) { appearance in
                ThemeManager.shared.current.agentBadge.resolve(appearance)
            })
        case .idle, .done:
            return Color(nsColor: NSColor(name: nil) { appearance in
                ThemeManager.shared.current.statusIdle.resolve(appearance)
            })
        }
    }

    var label: String {
        switch self {
        case .waitingPermission: return "PERMISSION"
        case .waitingInput: return "NEEDS INPUT"
        case .needsAttention: return "ERROR"
        case .working: return "WORKING"
        case .background: return "BACKGROUND"
        case .compacting: return "COMPACTING"
        case .done: return "DONE"
        case .idle: return "IDLE"
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .waitingPermission: return "waiting for permission"
        case .waitingInput: return "waiting for input"
        case .needsAttention: return "needs attention"
        case .working: return "working"
        case .background: return "working in background"
        case .compacting: return "compacting context"
        case .done: return "done"
        case .idle: return "idle"
        }
    }
}
