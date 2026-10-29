import SwiftUI

extension SessionStatus {
    var color: Color {
        switch self {
        case .waitingPermission: return Color.statusPermission
        case .waitingInput, .needsAttention: return Color.statusAttention
        case .working: return Color.statusGreen
        case .compacting:
            return Color(nsColor: NSColor(name: nil) { appearance in
                ThemeManager.shared.current.agentBadge.resolve(appearance)
            })
        case .idle, .done, .background:
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
        case .waitingPermission: return String(localized: "waiting for permission")
        case .waitingInput: return String(localized: "waiting for input")
        case .needsAttention: return String(localized: "needs attention")
        case .working: return String(localized: "working")
        case .background: return String(localized: "background tasks running")
        case .compacting: return String(localized: "compacting context")
        case .done: return String(localized: "done")
        case .idle: return String(localized: "idle")
        }
    }
}
