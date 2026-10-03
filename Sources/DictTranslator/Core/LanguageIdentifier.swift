import Foundation
import NaturalLanguage

/// 第二层：汉字为主、文字构成无法定论的文本（学校、寿司、手机、医院…）究竟是中文还是日语。
///
/// 这类文本没有任何单一可靠的信号，所以把几路证据按权重相加，分数为正判日语，否则判中文：
/// - 系统语言识别：判日语时很可靠；判中文时偏向中文，只算弱证据
/// - 有道词典收录：只有日语词典收录 → 日语；只有中文词典收录 → 中文；
///   两边都收录说明中日通用，没有信息；两边都没有多半是中文新词（新冠疫情、抖音）
/// - Google 语言检测（能连上时）
///
/// 权重和阈值来自对 200 多个中日词汇的实测（见 LanguageTests）。腾讯的检测对汉字文本一律返回中文，没有区分力，不使用。
enum LanguageIdentifier {
    struct Result {
        var lang: Lang
        var score: Double
        var trace: [String]
    }

    private enum Weight {
        static let recognizerJapanese = 4.0
        static let recognizerChinese = -1.5
        static let dictionaryJapaneseOnly = 4.0
        static let dictionaryChineseOnly = -3.5
        static let dictionaryMissing = -2.0
        static let jlptLevel = 1.0
        static let inChineseVocabulary = -1.2
        static let outsideChineseVocabulary = 1.0
        static let google = 3.0
        /// 本地证据已经足够，不再发网络请求
        static let confident = 3.5
    }

    private static let recognizerThreshold = 0.7
    /// 只对词和短语查词典
    private static let dictionaryMaxLength = 10
    private static let cache = NSCache<NSString, NSString>()

    /// 先看文字构成；歧义时才走证据合并
    @MainActor
    static func identify(_ text: String) async -> Result {
        if case .certain(let lang) = LanguageDetector.analyze(text) {
            return Result(lang: lang, score: lang == .ja ? .infinity : -.infinity, trace: ["script"])
        }
        return await resolveAmbiguous(text)
    }

    /// 系统自带的中文词向量词表（约 3 万常用词）。日语里的词多半不在其中；词表外的中文新词会被词典缺失扣分抵消
    private static let chineseVocabulary = NLEmbedding.wordEmbedding(for: .simplifiedChinese)
    private static let vocabularyMaxLength = 5

    static func vocabularyScore(_ text: String) -> Double {
        guard text.count <= vocabularyMaxLength, let vocabulary = chineseVocabulary else { return 0 }
        return vocabulary.contains(text) ? Weight.inChineseVocabulary : Weight.outsideChineseVocabulary
    }

    /// 本地证据：系统语言识别
    static func recognizerScore(_ text: String) -> Double {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.simplifiedChinese, .japanese]
        recognizer.processString(text)
        let scores = recognizer.languageHypotheses(withMaximum: 2)
        if (scores[.japanese] ?? 0) >= recognizerThreshold { return Weight.recognizerJapanese }
        if (scores[.simplifiedChinese] ?? 0) >= recognizerThreshold { return Weight.recognizerChinese }
        return 0
    }

    @MainActor
    static func resolveAmbiguous(_ text: String) async -> Result {
        let key = text as NSString
        if let hit = cache.object(forKey: key), let lang = Lang(rawValue: hit as String) {
            return Result(lang: lang, score: 0, trace: ["cache"])
        }

        var score = 0.0
        var trace: [String] = []
        func add(_ name: String, _ value: Double) {
            guard value != 0 else { return }
            score += value
            trace.append("\(name) \(value > 0 ? "+" : "")\(value)")
        }

        add("recognizer", recognizerScore(text))
        add("vocabulary", vocabularyScore(text))

        if abs(score) < Weight.confident, text.count <= dictionaryMaxLength, !Task.isCancelled {
            if let presence = await YoudaoDictService.presence(of: text) {
                switch (presence.japanese, presence.chinese) {
                case (true, false): add("dict-ja-only", Weight.dictionaryJapaneseOnly)
                case (false, true): add("dict-zh-only", Weight.dictionaryChineseOnly)
                case (false, false): add("dict-missing", Weight.dictionaryMissing)
                case (true, true): trace.append("dict-both")
                }
                if presence.hasJLPTLevel { add("jlpt", Weight.jlptLevel) }
            }
        }

        if abs(score) < Weight.confident, !MachineTranslator.isGoogleBlocked, !Task.isCancelled {
            do {
                switch try await GoogleTranslateService.detect(text) {
                case .ja: add("google-ja", Weight.google)
                case .zh: add("google-zh", -Weight.google)
                default: break
                }
            } catch {
                MachineTranslator.noteGoogleFailure(error)
            }
        }

        let lang: Lang = score > 0 ? .ja : .zh
        // 被取消或网络没取到证据时不缓存，避免把不完整的结论记下来
        if !Task.isCancelled, !trace.isEmpty { cache.setObject(lang.rawValue as NSString, forKey: key) }
        return Result(lang: lang, score: score, trace: trace)
    }
}
