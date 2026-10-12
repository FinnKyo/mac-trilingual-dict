import Foundation

/// 数词 + 量词的读音。IPADic 把「二十歳」切成「二/十/歳」逐字注音（に じゅう さい），
/// 「一人」读成いちにん、「一本」读成いちほん，这里把数词和后面的量词合并，按音变规则重新给读音
enum JapaneseNumerals {
    typealias Morpheme = JapaneseAnalyzer.Morpheme

    /// 量词的读音规则
    struct Counter {
        var kana: String
        /// 1、6、8、10、100 结尾时促音化（いっかい、ろっぽん、じゅっさつ）
        var geminates = false
        /// 促音化后的形式（ほん → ぽん）；nil 表示与 kana 相同
        var geminated: String? = nil
        /// 3、千、万、何 后面的浊音形式（さんぼん、なんがい）
        var afterN: String? = nil
        /// 4 后面的形式（よんぷん）
        var afterFour: String? = nil
        /// 末位数字的整体读音（よにん、くじ），十几、二十几也适用
        var lastDigit: [Int: String] = [:]
        /// 只有数值完全相同时才用的特殊读音（ひとり、はたち）
        var exact: [Int: String] = [:]
    }

    private static func h(_ kana: String, _ p: String, three: String, four: String? = nil) -> Counter {
        Counter(kana: kana, geminates: true, geminated: p, afterN: three, afterFour: four)
    }
    private static func gem(_ kana: String, three: String? = nil) -> Counter {
        Counter(kana: kana, geminates: true, afterN: three)
    }

    private static let days: [Int: String] = [
        1: "いちにち", 2: "ふつか", 3: "みっか", 4: "よっか", 5: "いつか", 6: "むいか", 7: "なのか",
        8: "ようか", 9: "ここのか", 10: "とおか", 14: "じゅうよっか", 20: "はつか", 24: "にじゅうよっか",
    ]

    static let counters: [String: Counter] = {
        var c: [String: Counter] = [
            "人": Counter(kana: "にん", lastDigit: [4: "よにん", 7: "しちにん"], exact: [1: "ひとり", 2: "ふたり"]),
            "日": Counter(kana: "にち", exact: days),
            "日間": Counter(kana: "にちかん", exact: days.mapValues { $0 + "かん" }),
            "年": Counter(kana: "ねん", lastDigit: [4: "よねん"]),
            "年間": Counter(kana: "ねんかん", lastDigit: [4: "よねんかん"]),
            "年生": Counter(kana: "ねんせい", lastDigit: [4: "よねんせい"]),
            "月": Counter(kana: "がつ", lastDigit: [4: "しがつ", 7: "しちがつ", 9: "くがつ"]),
            "時": Counter(kana: "じ", lastDigit: [4: "よじ", 7: "しちじ", 9: "くじ"]),
            "時間": Counter(kana: "じかん", lastDigit: [4: "よじかん", 9: "くじかん"]),
            "時半": Counter(kana: "じはん", lastDigit: [4: "よじはん", 7: "しちじはん", 9: "くじはん"]),
            "円": Counter(kana: "えん", lastDigit: [4: "よえん"]),
            "枚": Counter(kana: "まい"), "台": Counter(kana: "だい"), "秒": Counter(kana: "びょう"),
            "度": Counter(kana: "ど"), "番": Counter(kana: "ばん"), "番目": Counter(kana: "ばんめ"),
            "名": Counter(kana: "めい"), "位": Counter(kana: "い"), "号": Counter(kana: "ごう"),
            "倍": Counter(kana: "ばい"), "割": Counter(kana: "わり"), "部": Counter(kana: "ぶ"),
            "人前": Counter(kana: "にんまえ", lastDigit: [4: "よにんまえ"], exact: [1: "いちにんまえ"]),
            // は行：いっぽん さんぼん ろっぽん
            "本": h("ほん", "ぽん", three: "ぼん"),
            "杯": h("はい", "ぱい", three: "ばい"),
            "匹": h("ひき", "ぴき", three: "びき"),
            "分": h("ふん", "ぷん", three: "ぷん", four: "ぷん"),
            "分間": h("ふんかん", "ぷんかん", three: "ぷんかん", four: "ぷんかん"),
            "泊": h("はく", "ぱく", three: "ぱく", four: "ぱく"),
            "発": h("はつ", "ぱつ", three: "ぱつ", four: "ぱつ"),
            "歩": h("ほ", "ぽ", three: "ぽ", four: "ぽ"),
            // か行：いっかい ろっかい はっかい
            "回": gem("かい"), "個": gem("こ"), "曲": gem("きょく"), "件": gem("けん"),
            "階": gem("かい", three: "がい"), "軒": gem("けん", three: "げん"),
            "課": gem("か"), "首": gem("しゅ"), "期": gem("き"), "機": gem("き"),
            // さ行、た行：いっさつ はっさい じゅっとう
            "冊": gem("さつ"), "歳": gem("さい"), "才": gem("さい"), "足": gem("そく", three: "ぞく"),
            "週": gem("しゅう"), "週間": gem("しゅうかん"), "種類": gem("しゅるい"), "世紀": gem("せいき"),
            "頭": gem("とう"), "通": gem("つう"), "着": gem("ちゃく"), "点": gem("てん"), "丁目": gem("ちょうめ"),
        ]
        c["歳"]?.exact = [20: "はたち"]
        c["才"]?.exact = [20: "はたち"]
        for m in ["ヶ月", "か月", "カ月", "ケ月", "箇月", "ヵ月"] { c[m] = gem("かげつ") }
        for m in ["ヶ所", "か所", "カ所", "箇所", "ヵ所"] { c[m] = gem("かしょ") }
        return c
    }()

    /// 后面的「中」读じゅう（一日中、一年中）；「百人中」仍读ちゅう
    private static let durationCounters: Set<String> = ["日", "日間", "年", "年間", "時間", "週間", "ヶ月", "か月", "カ月", "ケ月", "箇月", "ヵ月"]

    // MARK: - 合并数词与量词

    /// 把连续的数词（及后面的量词）合并成一个带读音的片段
    static func apply(_ ms: [Morpheme]) -> [Morpheme] {
        var out: [Morpheme] = []
        var i = 0
        while i < ms.count {
            guard let num = number(in: ms, from: i) else {
                out.append(ms[i]); i += 1; continue
            }
            let (value, numSurface, isKanji, end) = (num.value, num.surface, num.isKanji, num.end)
            // 量词可能被切成一到两个片段（「日間」「時/間」）
            var counterKey: String?
            var counterEnd = end
            for len in [2, 1] where end + len <= ms.count {
                let s = ms[end..<(end + len)].map(\.surface).joined()
                if counters[s] != nil { counterKey = s; counterEnd = end + len; break }
            }

            guard let key = counterKey, let counter = counters[key] else {
                // 没有量词：汉字数字整体注音，阿拉伯数字和单独的「何」保持原样
                if isKanji, let v = value {
                    out.append(Morpheme(surface: numSurface, reading: reading(of: v), lemma: nil))
                } else {
                    out.append(contentsOf: ms[i..<end])
                }
                i = end; continue
            }

            // 「五月一日」「5月1日」的一日读ついたち
            let full = key == "日" && value == 1 && out.last?.surface.hasSuffix("月") == true
                ? "ついたち" : counterReading(value, counter)
            let surface = numSurface + key
            if !isKanji, let v = value, full == reading(of: v) + counter.kana {
                // 阿拉伯数字 + 规则读音（2024年、3人）：只给量词注音，不在数字上方堆一长串读音
                out.append(Morpheme(surface: numSurface, reading: nil, lemma: nil))
                out.append(Morpheme(surface: key, reading: counter.kana, lemma: nil))
            } else {
                // 一人、二十歳、三日 这类有固定词条的，可以点击查询
                let special = value.map { counter.exact[$0] != nil } ?? false
                var m = Morpheme(surface: surface, reading: full, lemma: special && isKanji ? surface : nil)
                // 一日中、一年中 的「中」读じゅう，和前面合成一个词注音
                if counterEnd < ms.count, ms[counterEnd].surface == "中", durationCounters.contains(key) {
                    m.surface += "中"
                    m.reading = full + "じゅう"
                    m.lemma = m.lemma.map { $0 + "中" }
                    counterEnd += 1
                }
                out.append(m)
            }
            i = counterEnd
        }
        return out
    }

    private struct Number {
        /// nil 表示「何」
        var value: Int?
        var surface: String
        var isKanji: Bool
        /// 数词之后的片段下标
        var end: Int
    }

    /// 从 i 开始的连续数词
    private static func number(in ms: [Morpheme], from i: Int) -> Number? {
        if ms[i].surface == "何" {
            return Number(value: nil, surface: "何", isKanji: true, end: i + 1)
        }
        var j = i
        var s = ""
        var kanji: Bool?
        while j < ms.count {
            let t = ms[j].surface
            guard let k = numeralKind(t), kanji == nil || kanji == k else { break }
            kanji = k
            s += t
            j += 1
        }
        guard let isKanji = kanji, let v = isKanji ? parseKanji(s) : Int(asciiDigits(s)) else { return nil }
        return Number(value: v, surface: s, isKanji: isKanji, end: j)
    }

    private static let kanjiDigits: [Character: Int] = [
        "〇": 0, "零": 0, "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9,
    ]
    private static let kanjiUnits: [Character: Int] = ["十": 10, "百": 100, "千": 1000]
    private static let kanjiGroups: [Character: Int] = ["万": 10_000, "億": 100_000_000]

    /// true：汉字数字；false：阿拉伯数字（含全角）；nil：不是数词
    private static func numeralKind(_ s: String) -> Bool? {
        guard !s.isEmpty else { return nil }
        if s.allSatisfy({ kanjiDigits[$0] != nil || kanjiUnits[$0] != nil || kanjiGroups[$0] != nil }) { return true }
        if s.unicodeScalars.allSatisfy({ (0x30...0x39).contains($0.value) || (0xFF10...0xFF19).contains($0.value) }) { return false }
        return nil
    }

    private static func asciiDigits(_ s: String) -> String {
        String(s.unicodeScalars.map { (0xFF10...0xFF19).contains($0.value) ? Character(Unicode.Scalar($0.value - 0xFF10 + 0x30)!) : Character($0) })
    }

    /// 「二十四」「三千五百」「二〇二四」→ 数值。单独的「万」「億」不当作数词
    static func parseKanji(_ s: String) -> Int? {
        let chars = Array(s)
        if chars.allSatisfy({ kanjiDigits[$0] != nil }) {
            // 逐位写法：二〇二四
            return chars.reduce(0) { $0 * 10 + kanjiDigits[$1]! }
        }
        guard let first = chars.first, kanjiGroups[first] == nil else { return nil }
        var total = 0, section = 0, digit: Int?
        for ch in chars {
            if let d = kanjiDigits[ch] {
                digit = (digit ?? 0) * 10 + d
            } else if let u = kanjiUnits[ch] {
                section += (digit ?? 1) * u
                digit = nil
            } else if let g = kanjiGroups[ch] {
                total += (section + (digit ?? 0)) * g
                section = 0
                digit = nil
            }
        }
        return total + section + (digit ?? 0)
    }

    // MARK: - 读音

    private static let digitNames = ["", "いち", "に", "さん", "よん", "ご", "ろく", "なな", "はち", "きゅう"]

    /// 数值的读音：さんびゃく、ろっぴゃく、はっせん 等音变
    static func reading(of n: Int) -> String {
        if n == 0 { return "れい" }
        var out = ""
        var rest = n
        for (g, name) in [(100_000_000, "おく"), (10_000, "まん")] where rest >= g {
            out += below10000(rest / g, isGroup: true) + name
            rest %= g
        }
        return out + below10000(rest, isGroup: false)
    }

    private static func below10000(_ n: Int, isGroup: Bool) -> String {
        var s = ""
        let th = n / 1000, hu = n / 100 % 10, te = n / 10 % 10, on = n % 10
        switch th {
        case 0: break
        case 1: s += isGroup ? "いっせん" : "せん"  // 一千万 いっせんまん
        case 3: s += "さんぜん"
        case 8: s += "はっせん"
        default: s += digitNames[th] + "せん"
        }
        switch hu {
        case 0: break
        case 1: s += "ひゃく"
        case 3: s += "さんびゃく"
        case 6: s += "ろっぴゃく"
        case 8: s += "はっぴゃく"
        default: s += digitNames[hu] + "ひゃく"
        }
        if te > 0 { s += (te == 1 ? "" : digitNames[te]) + "じゅう" }
        s += digitNames[on]
        return s
    }

    /// 数值 + 量词的读音；value 为 nil 表示「何」
    static func counterReading(_ value: Int?, _ c: Counter) -> String {
        guard let n = value else { return "なん" + (c.afterN ?? c.kana) }
        if let e = c.exact[n] { return e }
        let geminated = c.geminated ?? c.kana
        let d = n % 10
        if d != 0 {
            let head = n - d > 0 ? reading(of: n - d) : ""
            if let whole = c.lastDigit[d] { return head + whole }
            switch d {
            case 1 where c.geminates: return head + "いっ" + geminated
            case 6 where c.geminates: return head + "ろっ" + geminated
            case 8 where c.geminates: return head + "はっ" + geminated
            case 3: return head + "さん" + (c.afterN ?? c.kana)
            case 4: return head + "よん" + (c.afterFour ?? c.kana)
            default: return head + digitNames[d] + c.kana
            }
        }
        let r = reading(of: n)
        guard c.geminates else { return r + c.kana }
        if n % 100 != 0, r.hasSuffix("じゅう") {
            return r.dropLast(1) + "っ" + geminated  // じゅっぽん
        }
        // は行、か行在百后面促音化（ひゃっぽん、ひゃっかい），さ行、た行不变（ひゃくさつ）
        if n % 1000 != 0, r.hasSuffix("ひゃく"), c.geminated != nil || c.kana.first.map(isKRow) == true {
            return r.dropLast(1) + "っ" + geminated
        }
        if r.hasSuffix("ん") { return r + (c.afterN ?? c.kana) }  // せんぼん、いちまんぼん
        return r + c.kana
    }

    private static func isKRow(_ ch: Character) -> Bool { "かきくけこ".contains(ch) }
}
