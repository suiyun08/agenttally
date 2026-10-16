import AppKit
import KeyboardShortcuts
import Foundation

extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel")
    // Storage key is "refocus" (the old name) for backward compatibility with existing user shortcuts.
    static let navigate = Self("refocus", default: .init(.n, modifiers: [.control, .command]))
}

enum FileAccessSettings {
    static let filesAndFoldersURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!
    static let privacySecurityURL = URL(string: "x-apple.systempreferences:com.apple.preference.security")!
}

/// In-app language choice. "System" leaves macOS's per-app language order alone; the others pin
/// this app's `AppleLanguages`, which macOS reads only at launch, so a change needs a relaunch.
enum AppLanguage: String, CaseIterable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    static let defaultsKey = "appLanguage"
    private static let appleLanguagesKey = "AppleLanguages"

    /// The choice in effect for this process, read once at launch.
    static let launchSelection = current(in: .standard)

    var label: String {
        switch self {
        case .system: String(localized: "System")
        // Language names stay in their own language so they are recognizable from either UI.
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }

    static func current(in defaults: UserDefaults) -> AppLanguage {
        defaults.string(forKey: defaultsKey).flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    /// Saves the choice and the language order macOS will use on the next launch.
    func apply(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
        if self == .system {
            defaults.removeObject(forKey: Self.appleLanguagesKey)
        } else {
            defaults.set([rawValue], forKey: Self.appleLanguagesKey)
        }
    }

    /// Starts a fresh copy of the app after this one exits, then quits.
    @MainActor static func relaunchApp() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }
}

/// Panel width presets. Dragging a side edge of the panel settles on the nearest one.
enum PanelWidth: Int, CaseIterable {
    case standard = 320
    case wide = 400
    case wider = 480

    static let defaultsKey = "panelWidth"

    static var current: PanelWidth {
        PanelWidth(rawValue: UserDefaults.standard.integer(forKey: defaultsKey)) ?? .standard
    }

    /// The widths a drag can pass through on its way to a preset.
    static let range = CGFloat(standard.rawValue)...CGFloat(wider.rawValue)

    /// The preset a drag released at `width` settles on; a tie goes to the narrower one.
    static func nearest(to width: CGFloat) -> PanelWidth {
        allCases.min { abs(CGFloat($0.rawValue) - width) < abs(CGFloat($1.rawValue) - width) } ?? .standard
    }
}
