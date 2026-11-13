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

    /// 界面提示里的语言名（「识别为日语」）
    var chineseName: String {
        switch self {
        case .zh: return "中文"
        case .en: return "英语"
        case .ja: return "日语"
        }
    }

    /// 系统语音朗读用的语言（中文译文不朗读）
    var speechVoice: String? {
        switch self {
        case .zh: return nil
        case .en: return "en-US"
        case .ja: return "ja-JP"
        }
    }

    /// Bing 翻译语言代码
    var bingCode: String {
        switch self {
        case .zh: return "zh-Hans"
        case .en: return "en"
        case .ja: return "ja"
        }
    }

    /// 输入为该语言时要翻译成的语言：只做中英、中日互译（母语为中文，不做日英互译）
    var targets: [Lang] {
        switch self {
        case .zh: return [.en, .ja]
        case .en, .ja: return [.zh]
        }
    }
}
