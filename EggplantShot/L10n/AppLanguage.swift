import AppKit
import Foundation

/// User-facing language preference.
///
/// Default (`.system`): Simplified Chinese only when the OS preferred language is
/// zh-Hans / zh-CN; every other locale (including zh-Hant) uses English.
enum AppLanguagePreference: String, CaseIterable, Identifiable, Hashable {
    case system
    case english
    case simplifiedChinese

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .system: return L10n.tr("Follow System")
        case .english: return L10n.tr("English")
        case .simplifiedChinese: return L10n.tr("简体中文")
        }
    }
}

/// Resolves and applies the app language. Lookups go through a dedicated `.lproj`
/// bundle so we can enforce “简中 only when OS is 简中” without zh-Hant fallback.
enum AppLanguage {
    private static let preferenceKey = "appLanguagePreference"

    static var preference: AppLanguagePreference {
        get {
            let raw = UserDefaults.standard.string(forKey: preferenceKey) ?? AppLanguagePreference.system.rawValue
            return AppLanguagePreference(rawValue: raw) ?? .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: preferenceKey)
        }
    }

    /// BCP-47 code used for `.lproj` lookup (`en` or `zh-Hans`).
    static var resolvedCode: String {
        switch preference {
        case .english:
            return "en"
        case .simplifiedChinese:
            return "zh-Hans"
        case .system:
            return systemPrefersSimplifiedChinese ? "zh-Hans" : "en"
        }
    }

    /// Bundle for the resolved language (falls back to main / English).
    static var bundle: Bundle {
        if let path = Bundle.main.path(forResource: resolvedCode, ofType: "lproj"),
           let languageBundle = Bundle(path: path) {
            return languageBundle
        }
        if let path = Bundle.main.path(forResource: "en", ofType: "lproj"),
           let english = Bundle(path: path) {
            return english
        }
        return .main
    }

    /// True when the user’s preferred languages indicate Simplified Chinese.
    static var systemPrefersSimplifiedChinese: Bool {
        for identifier in Locale.preferredLanguages {
            let id = identifier.lowercased()
            if id.hasPrefix("zh-hans") || id.hasPrefix("zh-cn") {
                return true
            }
            if id.hasPrefix("zh-hant") || id.hasPrefix("zh-tw")
                || id.hasPrefix("zh-hk") || id.hasPrefix("zh-mo") {
                return false
            }
        }

        let language = Locale.current.language
        guard language.languageCode?.identifier == "zh" else { return false }
        if language.script?.identifier == "Hans" { return true }
        if language.script?.identifier == "Hant" { return false }
        return language.region?.identifier == "CN"
    }

    /// Persist preference and relaunch so menus, alerts, and AppKit tooltips refresh.
    @MainActor
    static func setPreferenceAndRelaunch(_ preference: AppLanguagePreference) {
        guard preference != self.preference else { return }
        self.preference = preference
        relaunch()
    }

    @MainActor
    static func relaunch() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}

/// Thin wrapper around `Localizable.strings` for the active `AppLanguage` bundle.
enum L10n {
    static func tr(_ key: String) -> String {
        AppLanguage.bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    static func tr(_ key: String, _ args: CVarArg...) -> String {
        String(format: tr(key), locale: Locale(identifier: AppLanguage.resolvedCode), arguments: args)
    }
}
