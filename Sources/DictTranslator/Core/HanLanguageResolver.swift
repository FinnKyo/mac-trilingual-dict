import Foundation
import NaturalLanguage

/// 划词、截图得到的纯汉字文本（不含假名）如何判定中文 / 日语
enum HanDetectionMode: String, CaseIterable, Identifiable {
    case online     // 在线识别（Google），失败时用本地识别
    case local      // 仅本地识别（字形 + 系统 NaturalLanguage）
    case chinese    // 总是按中文
    case japanese   // 总是按日语

    var id: String { rawValue }

    var title: String {
        switch self {
        case .online: return "自动识别：在线（Google）优先，失败时使用本地识别"
        case .local: return "自动识别：仅本地（字形 + 系统语言识别，无网络请求）"
        case .chinese: return "总是按中文查"
        case .japanese: return "总是按日语查"
        }
    }

    static var current: HanDetectionMode {
        HanDetectionMode(rawValue: UserDefaults.standard.string(forKey: SettingsKeys.hanDetection) ?? "") ?? .online
    }
}

/// 纯汉字文本的中日判定
@MainActor
enum HanLanguageResolver {
    enum ScriptHint: Equatable {
        case chinese    // 含简体专用字（日文字符集里没有），必定是中文
        case japanese   // 含「々」「〆」，必定是日语
        case leansJapanese  // 含日文新字体 / 繁体字（简体字符集里没有），多半是日语
        case none
    }

    private static let cache = NSCache<NSString, NSString>()

    /// 是否需要判定：识别为中文、含汉字且不含任何假名
    nonisolated static func needsResolution(_ text: String) -> Bool {
        LanguageDetector.detect(text) == .zh
            && text.unicodeScalars.contains(where: LanguageDetector.isCJKIdeograph)
            && !text.unicodeScalars.contains(where: LanguageDetector.isKana)
    }

    /// 无需等待网络即可确定的结果；返回 nil 表示需要调用 `resolve` 在线识别
    static func immediateResult(_ text: String, mode: HanDetectionMode = .current) -> Lang? {
        switch mode {
        case .chinese: return .zh
        case .japanese: return .ja
        case .local: return localGuess(text)
        case .online:
            switch scriptHint(text) {
            case .chinese: return .zh
            case .japanese: return .ja
            case .leansJapanese, .none: break
            }
            if let hit = cache.object(forKey: text as NSString) { return Lang(rawValue: hit as String) }
            return nil
        }
    }

    static func resolve(_ text: String, mode: HanDetectionMode = .current) async -> Lang {
        if let lang = immediateResult(text, mode: mode) { return lang }
        if let lang = await MachineTranslator.detectLanguage(text), lang != .en {
            cache.setObject(lang.rawValue as NSString, forKey: text as NSString)
            return lang
        }
        return localGuess(text)
    }

    /// 本地判定：先看字形，再用系统 NaturalLanguage；都没有明显倾向时按中文
    nonisolated static func localGuess(_ text: String) -> Lang {
        switch scriptHint(text) {
        case .chinese: return .zh
        case .japanese, .leansJapanese: return .ja
        case .none: break
        }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.japanese, .simplifiedChinese, .traditionalChinese]
        recognizer.processString(text)
        let h = recognizer.languageHypotheses(withMaximum: 3)
        let ja = h[.japanese] ?? 0
        let zh = (h[.simplifiedChinese] ?? 0) + (h[.traditionalChinese] ?? 0)
        return ja > zh ? .ja : .zh
    }

    /// 根据字符集判断：日文字符集（Shift_JIS）没有的字只会出现在中文里；
    /// 简体字符集（GB2312）没有、日文字符集有的字（駅、気、経、強…）多半是日语
    nonisolated static func scriptHint(_ text: String) -> ScriptHint {
        var leansJapanese = false
        for s in text.unicodeScalars {
            if s.value == 0x3005 || s.value == 0x3006 { return .japanese }   // 々 〆
            guard LanguageDetector.isCJKIdeograph(s) else { continue }
            let c = String(s)
            let inJIS = c.canBeConverted(to: .shiftJIS)
            let inGB = c.canBeConverted(to: gb2312)
            if !inJIS && inGB { return .chinese }
            if inJIS && !inGB { leansJapanese = true }
        }
        return leansJapanese ? .leansJapanese : .none
    }

    private nonisolated static let gb2312 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.EUC_CN.rawValue)))
}
