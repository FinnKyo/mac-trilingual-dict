import Foundation
import Dictionary
import Mecab_Swift

/// 日语形态素分析（MeCab + IPADic）：分词、读音、词的原形
enum JapaneseAnalyzer {
    struct Morpheme {
        var surface: String
        /// 平假名读音；词典里没有（未登录词、符号）时为 nil
        var reading: String?
        /// 原形（「行っ」→「行く」）；只有实词有，助词、助动词、符号等为 nil
        var lemma: String?
        /// 动词、形容词后面的活用部分（た、ます、て、いる…），和前面算同一个词：一起高亮、点击查前面的原形
        var attachesToPrevious = false
    }

    /// 词典打不开时为 nil，调用方退回系统分词器
    private static let tokenizer: Tokenizer? = {
        guard let url = dictionaryURL() else {
            NSLog("JapaneseAnalyzer: IPADic not found")
            return nil
        }
        do { return try Tokenizer(dictionary: IPADicProvider(url: url)) }
        catch { NSLog("JapaneseAnalyzer: \(error)"); return nil }
    }()
    /// MeCab 的 tagger 不能同时在多个线程使用
    private static let lock = NSLock()

    static var isAvailable: Bool { tokenizer != nil }

    /// 返回覆盖全文的片段（MeCab 跳过的空白、换行作为无读音的片段补回）；词典不可用时返回 nil
    static func analyze(_ text: String) -> [Morpheme]? {
        guard let tokenizer else { return nil }
        let annotations = lock.withLock { tokenizer.tokenize(text: text, transliteration: .katakana) }

        var out: [Morpheme] = []
        var cursor = text.startIndex
        var afterInflecting = false
        for a in annotations where a.range.lowerBound >= cursor {
            if a.range.lowerBound > cursor {
                out.append(Morpheme(surface: String(text[cursor..<a.range.lowerBound]), reading: nil, lemma: nil))
                afterInflecting = false
            }
            let surface = String(text[a.range])
            cursor = a.range.upperBound
            // 未登录词没有读音字段，Mecab-Swift 会用原文代替
            let (reading, dictionaryForm) = disambiguate(surface, reading: readingFixes[surface] ?? a.reading.hiragana,
                                                         lemma: a.dictionaryForm, after: out)
            let hasReading = !reading.isEmpty && reading.unicodeScalars.allSatisfy(LanguageDetector.isKana)
            // 「,」「.」这类被当成名词的符号不可点击
            let content = Self.isContentWord(a.partOfSpeech) && surface.unicodeScalars.contains { CharacterSet.letters.contains($0) }
            let lemma = dictionaryForm.isEmpty || dictionaryForm == "*" ? surface : dictionaryForm
            // IPADicProvider 把助动词、补助动词标成 .unknown
            let attaches = afterInflecting && (a.partOfSpeech == .unknown || ["て", "で", "ちゃ", "じゃ"].contains(surface))
            out.append(Morpheme(surface: surface,
                                reading: hasReading ? reading : nil,
                                lemma: content ? lemma : nil,
                                attachesToPrevious: attaches))
            afterInflecting = attaches || a.partOfSpeech == .verb || a.partOfSpeech == .adjective
        }
        if cursor < text.endIndex {
            out.append(Morpheme(surface: String(text[cursor...]), reading: nil, lemma: nil))
        }
        return out
    }

    /// 同形异读的活用形，MeCab 常选错，按前文改正
    private static func disambiguate(_ surface: String, reading: String, lemma: String, after out: [Morpheme]) -> (String, String) {
        // 「行った」既可能是行く也可能是行う；只有「〜を行った」才是行う
        if surface == "行っ", lemma == "行う", out.last?.surface != "を" {
            return ("いっ", "行く")
        }
        // 「降り」既是降る也是降りる的连用形；「雨が降りそう」会被判成降りる
        if surface == "降り", lemma == "降りる" {
            let prev = out.suffix(2).map(\.surface)
            if prev.count == 2, ["雨", "雪", "雹", "霰", "霙", "小雨", "大雨", "大雪"].contains(prev[0]), ["が", "も", "は"].contains(prev[1]) {
                return ("ふり", "降る")
            }
        }
        return (reading, lemma)
    }

    /// IPADic 的读音与通常的标注不一致的词
    private static let readingFixes = ["日本": "にほん", "日本人": "にほんじん"]

    private static func isContentWord(_ pos: PartOfSpeech) -> Bool {
        switch pos {
        case .noun, .verb, .adjective, .adverb: return true
        default: return false
        }
    }

    /// SwiftPM 把 IPADic 打包成 Mecab-Swift_IPADic.bundle：.app 里在 Resources，命令行调试时在可执行文件旁边，
    /// 单元测试时在测试 bundle 旁边。不用 IPADic() 是因为它找不到资源时会直接崩溃
    private static func dictionaryURL() -> URL? {
        let name = "Mecab-Swift_IPADic.bundle"
        let exeDir = Bundle.main.executableURL?.deletingLastPathComponent()
        let moduleDir = Bundle(for: BundleToken.self).bundleURL.deletingLastPathComponent()
        let candidates = [Bundle.main.resourceURL, Bundle.main.bundleURL, exeDir, moduleDir].compactMap { $0?.appendingPathComponent(name) }
        for url in candidates {
            if let dict = Bundle(url: url)?.url(forResource: "ipadic dictionary", withExtension: nil) { return dict }
            let flat = url.appendingPathComponent("ipadic dictionary")
            if FileManager.default.fileExists(atPath: flat.appendingPathComponent("sys.dic").path) { return flat }
        }
        return nil
    }
}

private final class BundleToken {}

/// IPADic 的字段位置和词性（按 pos-id.def 的编号；Mecab-Swift 自带的映射把形容词当成了副词）
private struct IPADicProvider: DictionaryProviding {
    let url: URL
    var dictionaryFormIndex: Int { 6 }
    var readingIndex: Int { 7 }
    var pronunciationIndex: Int { 8 }

    func partOfSpeech(posID: UInt16) -> PartOfSpeech {
        switch posID {
        case 2: return .adverb               // 感動詞（ありがとう）
        case 10: return .adjective           // 形容詞,自立
        case 31: return .verb                // 動詞,自立
        case 34, 35: return .adverb          // 副詞
        case 36...47, 59...61, 67: return .noun  // 一般・サ変・固有名詞・代名詞・副詞可能 等
        case 27...30, 50...58: return .prefix    // 接頭詞、接尾
        case 0, 1, 3...9: return .symbol
        case 11, 12, 25, 32, 33: return .unknown  // 助動詞、動詞・形容詞の接尾／非自立（た、ます、れる、いる、ない）
        default: return .particle            // 助詞、名詞非自立、連体詞、接続詞、数
        }
    }
}
