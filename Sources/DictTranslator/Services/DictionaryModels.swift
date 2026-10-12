import Foundation

/// 一个带注音的日文片段（用于 furigana 显示）
struct RubyToken: Hashable {
    var surface: String
    var reading: String?   // 平假名读音；与 surface 相同或无汉字时为 nil
    /// 所属单词的原形（「行った」→「行く」），可点击查询；助词、符号等为 nil
    var lemma: String? = nil
    /// 所属单词在句子中的序号：同一个词拆成的多个片段（「行」「った」）序号相同，一起高亮
    var word: Int? = nil
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

/// 发音来源
enum PronunciationSource: Hashable {
    /// 直接给出音频地址（有道的英语发音）
    case url(URL?)
    /// MOJi 辞書的真人发音：type 102 为单词，103 为例句；取不到时用系统语音读 text
    case moji(id: String, type: Int, text: String)
    /// 系统语音合成（离线），language 如 "ja-JP"
    case speech(text: String, language: String)
}

/// 日语词条（MOJi 辞書）
struct JapaneseEntry {
    struct Example: Hashable {
        var tokens: [RubyToken]
        var translation: String
        var audio: PronunciationSource?
    }
    struct Sense: Hashable {
        var chinese: String
        var examples: [Example]
    }

    var id: String
    var headword: String
    var reading: String?           // 假名读音；与词头相同时为 nil
    var tone: String?              // 声调，如「②」
    var romaji: String?
    var examTypes: [String]        // N5、考研…
    var partOfSpeech: String       // 词性，如「他动·一段」
    var senses: [Sense]
    var origin: String?            // 外来语原词，如 computer
    var audio: PronunciationSource
    /// 同一次搜索里的其他词条（同音词、相关词组），可点击查看
    var related: [JapaneseCandidate] = []
}

/// 日语词条的搜索结果（只有概要）
struct JapaneseCandidate: Hashable {
    var id: String
    var spell: String
    var reading: String?
    var tone: String?
    var tags: [String]
    var excerpt: String            // 「[名] 食物；食品」
}

/// 国语辞典（日日辞典）的释义，来自《デジタル大辞泉》
struct KokugoEntry {
    var heading: String            // 「か・ける【掛ける／懸ける】」
    var lines: [String]            // 按原文段落，义项编号单独成行时已与正文合并
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

/// 中文 → 日文：可能的日语对应词（MOJi 辞書），点击查看完整词条
struct ChineseJapaneseEntry {
    var candidates: [JapaneseCandidate]
}
