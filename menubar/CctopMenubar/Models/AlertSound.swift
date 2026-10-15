import AppKit
import os

private let alertSoundLogger = Logger(subsystem: "com.st0012.CctopMenubar", category: "AlertSound")

/// A sound cctop plays when a session needs a look. Bundled sounds ship as `<rawValue>.caf`
/// in the app's resources.
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

    @MainActor private static var player: NSSound?

    /// Plays the sound once, cutting off one still playing.
    @MainActor func play() {
        Self.player?.stop()
        Self.player = nil
        switch self {
        case .silent:
            return
        case .systemDefault:
            NSSound.beep()
        default:
            guard let url = Bundle.main.url(forResource: rawValue, withExtension: "caf") else { return }
            Self.player = NSSound(contentsOf: url, byReference: true)
            Self.player?.play()
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

    /// Plays this event's chosen sound. Independent of notifications: banners off still ring.
    @MainActor func ring() {
        let sound = sound()
        alertSoundLogger.notice("Ringing \(sound.rawValue, privacy: .public) for \(String(describing: self), privacy: .public)")
        sound.play()
    }

    /// The events one refresh rings: one per event, for sessions already listed that just
    /// changed into it. A session first seen in this refresh, as every session is at launch,
    /// rings nothing.
    static func events(
        newUserSessions: [UserSession], oldUserSessions: [UserSession]
    ) -> Set<AlertSoundEvent> {
        let oldStatusByID: [String: SessionStatus] = Dictionary(
            oldUserSessions.compactMap { session in
                session.identity.cctopSessionID.map { ($0, session.displayRecord.data.status) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        var events: Set<AlertSoundEvent> = []
        for session in newUserSessions {
            guard let id = session.identity.cctopSessionID,
                  let oldStatus = oldStatusByID[id],
                  let event = AlertSoundEvent(status: session.displayRecord.data.status),
                  AlertSoundEvent(status: oldStatus) != event else { continue }
            events.insert(event)
        }
        return events
    }
}
