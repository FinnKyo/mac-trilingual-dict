import Foundation
import NaturalLanguage

/// 区分中文与日语。纯汉字文本（影響、大丈夫）单看字符无法判断，需要借助识别服务：
/// 系统本地识别（置信度够高才采用）→ Google → 腾讯 → 都没有结论时按中文
enum LanguageIdentifier {
    private static let confidentScore = 0.85
    private static let cache = NSCache<NSString, NSString>()

    /// 系统自带的语言识别（本地、即时）。拿不准时返回 nil
    static func local(_ text: String) -> Lang? {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.simplifiedChinese, .traditionalChinese, .japanese]
        recognizer.processString(text)
        let scores = recognizer.languageHypotheses(withMaximum: 3)
        let ja = scores[.japanese] ?? 0
        let zh = (scores[.simplifiedChinese] ?? 0) + (scores[.traditionalChinese] ?? 0)
        if ja >= confidentScore { return .ja }
        if zh >= confidentScore { return .zh }
        return nil
    }

    @MainActor
    static func resolve(_ text: String) async -> Lang {
        let key = text as NSString
        if let hit = cache.object(forKey: key), let lang = Lang(rawValue: hit as String) { return lang }

        var result = local(text)
        if result == nil, !MachineTranslator.isGoogleBlocked {
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
}
