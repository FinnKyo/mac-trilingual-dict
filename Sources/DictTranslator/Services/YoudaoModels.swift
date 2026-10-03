import Foundation

/// 一个带注音的日文片段（用于 furigana 显示）
struct RubyToken: Hashable {
    var surface: String
    var reading: String?   // 平假名读音；与 surface 相同或无汉字时为 nil
}

struct EnglishEntry {
    struct Definition: Hashable { var pos: String; var text: String }
    struct WordForm: Hashable { var name: String; var value: String }
    struct Phrase: Hashable { var phrase: String; var meaning: String }
    struct Sentence: Hashable { var english: String; var chinese: String }

    var word: String
    var ukPhone: String?
    var usPhone: String?
    var examTypes: [String]
    var definitions: [Definition]
    var wordForms: [WordForm]
    var phrases: [Phrase]
    var sentences: [Sentence]
    var webTranslations: [String]
}

struct JapaneseEntry {
    struct BriefDefinition: Hashable { var pos: String; var meanings: [String] }
    struct Example: Hashable {
        var tokens: [RubyToken]
        var translation: String
    }
    struct Meaning: Hashable {
        var chinese: String
        var japanese: String
        var examples: [Example]
    }
    struct Sense: Hashable {
        var category: String   // 词性/分类，如「他动词・一段/二类」
        var meanings: [Meaning]
    }

    var headword: String
    var hiragana: String?
    var katakana: String?
    var romaji: String?
    var tone: String?
    var examTypes: [String]
    var brief: [BriefDefinition]
    var senses: [Sense]
    var origin: String?        // 外来语原词，如 computer
    var audioText: String      // 用于发音的文本

    /// 读音是否需要显示（纯假名词条读音与词头相同则不必重复）
    var readingDiffersFromHeadword: Bool {
        guard let h = hiragana, !h.isEmpty else { return false }
        return h != headword && (katakana ?? "") != headword
    }
}

/// 中文 → 英文 词条
struct ChineseEnglishEntry {
    struct Item: Hashable {
        var pos: String
        var words: [String]     // 英文对应词（可点击查词）
        var explanation: String // 英文对应词的中文解释
    }
    var pinyin: String?
    var items: [Item]
}

/// 中文 → 日文 词条
struct ChineseJapaneseEntry {
    struct Example: Hashable {
        var chinese: String
        var japaneseTokens: [RubyToken]
    }
    var pinyin: String?
    var words: [String]       // 日文对应词
    var examples: [Example]
}
