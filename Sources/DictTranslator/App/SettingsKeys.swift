import Foundation

enum SettingsKeys {
    static let engine = "translationEngine"
    static let selectionEnabled = "selectionEnabled"
    static let blacklist = "selectionBlacklist"
    static let iconDismissDelay = "iconDismissDelay"
    static let onboardingShown = "onboardingShown"

    static let defaultBlacklist = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.apple.dt.Xcode",
        "com.microsoft.VSCode",
        "com.apple.finder",
    ]

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            engine: TranslationEngine.googleWithFallback.rawValue,
            selectionEnabled: true,
            blacklist: defaultBlacklist,
            iconDismissDelay: 4.0,
        ])
    }

    static var blacklistedBundleIDs: [String] {
        UserDefaults.standard.stringArray(forKey: blacklist) ?? defaultBlacklist
    }
}
