import AppKit
import UserNotifications

/// A sound a notification can play. Bundled sounds ship as `<rawValue>.caf` in the app's resources.
enum AlertSound: String, CaseIterable {
    case newNotification = "cctop-new-notification"
    case bell = "cctop-bell"
    case message = "cctop-message"
    case chime = "cctop-notification"
    case simple = "cctop-simple"
    case systemDefault = "system-default"
    case silent = "none"

    var label: String {
        switch self {
        case .newNotification: String(localized: "New Notification")
        case .bell: String(localized: "Bell")
        case .message: String(localized: "Message")
        case .chime: String(localized: "Chime")
        case .simple: String(localized: "Simple")
        case .systemDefault: String(localized: "System Default")
        case .silent: String(localized: "None")
        }
    }

    /// The bundled file name, or nil for the system sound and silence.
    var fileName: String? {
        switch self {
        case .systemDefault, .silent: nil
        default: "\(rawValue).caf"
        }
    }

    /// What a notification carries for this choice; nil keeps it silent.
    var notificationSound: UNNotificationSound? {
        switch self {
        case .silent: return nil
        case .systemDefault: return .default
        default: return fileName.map { UNNotificationSound(named: UNNotificationSoundName($0)) }
        }
    }

    @MainActor private static var previewPlayer: NSSound?

    /// Plays the sound once, as a preview when it is picked in Settings.
    @MainActor func preview() {
        Self.previewPlayer?.stop()
        Self.previewPlayer = nil
        switch self {
        case .silent:
            return
        case .systemDefault:
            NSSound.beep()
        default:
            guard let url = Bundle.main.url(forResource: rawValue, withExtension: "caf") else { return }
            Self.previewPlayer = NSSound(contentsOf: url, byReference: true)
            Self.previewPlayer?.play()
        }
    }
}

/// The two moments that ring: a finished turn, and a session that needs the user.
enum AlertSoundEvent: CaseIterable {
    case done
    /// A permission request, a question, or an error stop.
    case needsYou

    init?(status: SessionStatus) {
        if status == .done {
            self = .done
        } else if status.needsAttention {
            self = .needsYou
        } else {
            return nil
        }
    }

    var title: String {
        switch self {
        case .done: String(localized: "Finished Sound")
        case .needsYou: String(localized: "Waiting Sound")
        }
    }

    var defaultsKey: String {
        switch self {
        case .done: "doneAlertSound"
        case .needsYou: "needsYouAlertSound"
        }
    }

    var defaultSound: AlertSound {
        switch self {
        case .done: .newNotification
        case .needsYou: .bell
        }
    }

    func sound(in defaults: UserDefaults = .standard) -> AlertSound {
        defaults.string(forKey: defaultsKey).flatMap(AlertSound.init(rawValue:)) ?? defaultSound
    }
}
