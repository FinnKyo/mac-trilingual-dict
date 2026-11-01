import Foundation

/// 中文单词 → 日语时的「同形异义」检查。
///
/// 机器翻译遇到中日写法相同的词常常照搬字形：床 → 床（日语是「地板」）、娘 → 娘（「女儿」）、
/// 丈夫 → 丈夫（「结实」）、怪我 → けが（「受伤」）。MOJi 的搜索结果带中文释义，据此判断：
/// - 同形词：写法和中文相同（繁简视为相同）的日语词；它的释义里没有这个中文词，就是同形异义
/// - 对应词：写法不同、释义里有这个中文词的日语词（床 → ベッド「床；床铺」，丈夫 → 夫「丈夫；老公」）
enum FalseFriendDetector {
    /// 机器翻译照搬了字形（或写成了同形词的读音）、日语里意思却不同时，返回那个同形词。
    /// 译文本身就是词典给出的对应词时不算（equivalents）
    static func falseFriend(_ word: String, translation: String, candidates: [JapaneseCandidate],
                            equivalents: [JapaneseCandidate] = []) -> JapaneseCandidate? {
        let t = translation.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let homographs = candidates.filter { isHomograph($0, of: word) }
        let matched: JapaneseCandidate?
        if t.unicodeScalars.contains(where: LanguageDetector.isCJKIdeograph) {
            // 勉強する、走る：去掉词尾的假名再比较；同形词有几个读音时取 MOJi 排第一的（最常用的）
            matched = sameCharacters(stripTrailingKana(t), word) ? homographs.first : nil
        } else {
            // けが：译成了同形词的读音
            matched = homographs.first { $0.reading.map { $0.hiragana == t.hiragana } ?? false }
        }
        guard let m = matched else { return nil }
        if equivalents.contains(where: { $0.spell == t || stripTrailingKana($0.spell) == stripTrailingKana(t) }) { return nil }
        return senses(of: m).isEmpty || meansSame(m, as: word) ? nil : m
    }

    /// 搜索结果里写法和中文不同、释义里有这个中文词的日语词；释义第一项就是该词的排前面
    static func glossEquivalents(_ word: String, candidates: [JapaneseCandidate]) -> [JapaneseCandidate] {
        candidates.enumerated()
            .compactMap { i, c -> (rank: Int, index: Int, c: JapaneseCandidate)? in
                guard !isHomograph(c, of: word), let pos = senses(of: c).firstIndex(of: word) else { return nil }
                return (pos == 0 ? 0 : 1, i, c)
            }
            .sorted { ($0.rank, $0.index) < ($1.rank, $1.index) }
            .map(\.c)
    }

    /// 列表里标「同形异义」用，比 meansSame 保守：释义里完全没有出现这个中文词才算（床 とこ「床铺」不标）
    static func isClearlyDifferent(_ c: JapaneseCandidate, from word: String) -> Bool {
        let s = senses(of: c)
        return isHomograph(c, of: word) && !s.isEmpty && !s.contains { $0.contains(word) }
    }

    /// 写法和中文词相同（繁简视为相同，忽略词尾假名：走 / 走る）
    static func isHomograph(_ c: JapaneseCandidate, of word: String) -> Bool {
        sameCharacters(stripTrailingKana(c.spell), word)
    }

    /// 释义里有这个中文词：中日同形同义（电话 / 電話）。两字以上的词出现在释义中即可（有名 →「有名气」）；
    /// 单字词要整项相同，否则「信」会因为「信任」「信件」被当成同义
    static func meansSame(_ c: JapaneseCandidate, as word: String) -> Bool {
        senses(of: c).contains { $0 == word || (word.count >= 2 && $0.contains(word)) }
    }

    /// 「[名·形动] 便利；方便；合适（俗）」→ ["便利", "方便", "合适"]
    static func senses(of c: JapaneseCandidate) -> [String] {
        var s = c.excerpt
        if s.hasPrefix("["), let close = s.firstIndex(of: "]") { s = String(s[s.index(after: close)...]) }
        s = s.replacingOccurrences(of: #"（[^）]*）|\([^)]*\)"#, with: "", options: .regularExpression)
        return s.components(separatedBy: CharacterSet(charactersIn: "；;，,、/：:。"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// 繁简、中日字形不同的同一个词（学习 / 学習）视为相同
    static func sameCharacters(_ a: String, _ b: String) -> Bool {
        guard a.count == b.count else { return false }
        return a == b || traditional(a) == traditional(b)
    }

    private static func traditional(_ s: String) -> String {
        s.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? s
    }

    /// 走る → 走，勉強する → 勉強；没有汉字时原样返回
    private static func stripTrailingKana(_ s: String) -> String {
        guard s.unicodeScalars.contains(where: LanguageDetector.isCJKIdeograph) else { return s }
        var t = Substring(s)
        while let last = t.unicodeScalars.last, LanguageDetector.isKana(last) { t = t.dropLast() }
        return String(t)
    }
}
