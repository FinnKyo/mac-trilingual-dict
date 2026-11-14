import Foundation

enum SettingsKeys {
    /// 句子翻译服务的尝试顺序与未启用的服务（rawValue 数组）
    static let engineOrder = "translationEngineOrder"
    static let engineDisabled = "translationEngineDisabled"
    /// 旧版本：单选的服务 + 失败时换用其他服务，只用于迁移
    static let engine = "translationEngine"
    static let engineFallback = "translationEngineFallback"
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
            selectionEnabled: true,
            blacklist: defaultBlacklist,
            iconDismissDelay: 4.0,
        ])
        TranslationEngine.migrateLegacySetting()
    }

    static var blacklistedBundleIDs: [String] {
        UserDefaults.standard.stringArray(forKey: blacklist) ?? defaultBlacklist
    }
}
