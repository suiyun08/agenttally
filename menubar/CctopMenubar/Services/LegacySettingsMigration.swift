import Foundation

/// Carries settings over from the app's previous identity (cctop, `com.st0012.CctopMenubar`) the
/// first time it runs as AgentTally: theme, language, panel width and position, sounds, shortcuts,
/// and which finished sessions were already seen. It runs once and never overwrites a setting
/// AgentTally already has.
enum LegacySettingsMigration {
    static let legacyDomain = "com.st0012.CctopMenubar"
    static let doneKey = "migratedFromCctopSettings"
    private static let appleLanguagesKey = "AppleLanguages"

    /// The legacy settings worth copying: everything the new domain lacks.
    static func settingsToCopy(legacy: [String: Any], current: [String: Any]) -> [String: Any] {
        legacy.filter { key, _ in current[key] == nil && key != doneKey }
    }

    /// Copies the legacy settings once. Returns true when it copied a language order, which macOS
    /// reads only at launch, so the caller should relaunch to show the chosen language.
    @discardableResult
    static func run(
        into defaults: UserDefaults = .standard,
        currentDomain: String? = Bundle.main.bundleIdentifier,
        legacyDomain: String = LegacySettingsMigration.legacyDomain
    ) -> Bool {
        guard let currentDomain, currentDomain != legacyDomain, !defaults.bool(forKey: doneKey) else { return false }
        let copied = settingsToCopy(
            legacy: defaults.persistentDomain(forName: legacyDomain) ?? [:],
            current: defaults.persistentDomain(forName: currentDomain) ?? [:]
        )
        for (key, value) in copied {
            defaults.set(value, forKey: key)
        }
        defaults.set(true, forKey: doneKey)
        return copied[appleLanguagesKey] != nil
    }
}
