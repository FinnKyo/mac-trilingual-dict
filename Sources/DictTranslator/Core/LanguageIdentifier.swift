import Foundation
import NaturalLanguage

/// 区分中文与日语。汉字为主的文本（影響、大丈夫）中日写法可能相同，按下面的顺序判断：
/// 1. 本地规则：含繁体字 / 日语新字体 → 日语（用户只用简体中文）；系统识别明确为简体中文 / 日语
/// 2. 在线检测：Google → 腾讯
/// 3. 都没有结论时按中文
enum LanguageIdentifier {
    private static let confidentScore = 0.85
    private static let cache = NSCache<NSString, NSString>()

    /// 本地即时判断。拿不准时返回 nil
    static func local(_ text: String) -> Lang? {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.simplifiedChinese, .traditionalChinese, .japanese]
        recognizer.processString(text)
        let scores = recognizer.languageHypotheses(withMaximum: 3)
        // 简体特征明显时直接判中文，不让个别生僻简体字触发下面的规则
        if (scores[.simplifiedChinese] ?? 0) >= confidentScore { return .zh }
        if LanguageDetector.hasNonSimplifiedHan(text) { return .ja }
        if (scores[.japanese] ?? 0) >= confidentScore { return .ja }
        return nil
    }

    /// 在线检测，没有结论时按中文
    @MainActor
    static func online(_ text: String) async -> Lang {
        let key = text as NSString
        if let hit = cache.object(forKey: key), let lang = Lang(rawValue: hit as String) { return lang }

        var result: Lang?
        if !MachineTranslator.isGoogleBlocked {
            do { result = try await GoogleTranslateService.detect(text) }
            catch { MachineTranslator.noteGoogleFailure(error) }
        }
        if Task.isCancelled { return .zh }
        if result == nil {
            result = try? await TencentTranslateService.detect(text)
        }
        // 只在中日之间取舍；其他结果一律当中文
        let lang: Lang = result == .ja ? .ja : .zh
        if !Task.isCancelled { cache.setObject(lang.rawValue as NSString, forKey: key) }
        return lang
    }

    @MainActor
    static func resolve(_ text: String) async -> Lang {
        if let lang = local(text) { return lang }
        return await online(text)
    }
}
