import Foundation

enum Lang: String, CaseIterable, Identifiable, Codable {
    case zh, en, ja

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .zh: return "中文"
        case .en: return "English"
        case .ja: return "日本語"
        }
    }

    var shortLabel: String {
        switch self {
        case .zh: return "中"
        case .en: return "英"
        case .ja: return "日"
        }
    }

    /// Google 翻译语言代码
    var googleCode: String {
        switch self {
        case .zh: return "zh-CN"
        case .en: return "en"
        case .ja: return "ja"
        }
    }

    var localeLanguage: Locale.Language {
        switch self {
        case .zh: return Locale.Language(identifier: "zh-Hans")
        case .en: return Locale.Language(identifier: "en")
        case .ja: return Locale.Language(identifier: "ja")
        }
    }

    /// 输入为该语言时需要展示的另外两种语言
    var others: [Lang] {
        switch self {
        case .zh: return [.en, .ja]
        case .en: return [.zh, .ja]
        case .ja: return [.zh, .en]
        }
    }
}
