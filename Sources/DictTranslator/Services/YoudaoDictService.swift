import Foundation

/// 有道词典网页版 jsonapi
enum YoudaoDictService {
    /// le: "en" 英汉/汉英, "ja" 日汉/汉日
    private final class CacheEntry { let value: JSONValue; init(_ v: JSONValue) { value = v } }
    private static let cache = NSCache<NSString, CacheEntry>()

    static func fetch(_ query: String, le: String, session: URLSession = HTTP.session) async throws -> JSONValue {
        // 同一个词在返回、重试、补充词条时会重复查询，缓存成功的结果
        let key = "\(le)|\(query)" as NSString
        if let hit = cache.object(forKey: key) { return hit.value }
        guard let url = HTTP.url("https://dict.youdao.com/jsonapi",
                                 query: ["q": query, "le": le, "client": "web", "keyfrom": "webdict"]) else {
            throw TranslatorError.badResponse
        }
        let data = try await HTTP.get(url, referer: "https://dict.youdao.com/", session: session)
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { throw TranslatorError.badResponse }
        let value = JSONValue(obj)
        cache.setObject(CacheEntry(value), forKey: key)
        return value
    }

    struct Presence {
        var japanese: Bool      // 日汉词典收录
        var chinese: Bool       // 汉日词典收录
        var hasJLPTLevel: Bool  // 是日语能力考试词汇
    }

    /// 一个汉字词在日语词典、中文词典里分别有没有收录（同一次请求，结果会缓存供后续查词复用）。
    /// 只有一边收录时可以据此判断语言；网络失败返回 nil
    static func presence(of word: String) async -> Presence? {
        guard let root = try? await fetch(word, le: "ja", session: HTTP.detectSession) else { return nil }
        return Presence(
            japanese: root["newjc"]["word"].hasContent || root["jc"]["word"].hasContent,
            chinese: root["cj"]["word"].hasContent || root["newcj"].hasContent,
            hasJLPTLevel: !root["newjc"]["exam_type"].stringArray.isEmpty
        )
    }

    // MARK: - 英 → 中

    static func lookupEnglish(_ word: String) async throws -> EnglishEntry? {
        parseEnglish(try await fetch(word, le: "en"), query: word)
    }

    static func parseEnglish(_ root: JSONValue, query: String) -> EnglishEntry? {
        let ec = root["ec"]
        let w = ec["word"].array.first ?? JSONValue(nil)

        var defs: [EnglishEntry.Definition] = []
        for tr in w["trs"].array {
            for t in tr["tr"].array {
                let text = t["l"]["i"].flattenedText
                guard !text.isEmpty else { continue }
                defs.append(splitPOS(text))
            }
        }

        let forms: [EnglishEntry.WordForm] = w["wfs"].array.compactMap { item in
            let wf = item["wf"]
            guard let name = wf["name"].nonEmptyString, let value = wf["value"].nonEmptyString else { return nil }
            return EnglishEntry.WordForm(name: name, value: value)
        }

        let phrases: [EnglishEntry.Phrase] = root["phrs"]["phrs"].array.prefix(8).compactMap { item in
            let phr = item["phr"]
            let head = phr["headword"]["l"]["i"].flattenedText
            let meaning = phr["trs"].array.map { $0["tr"]["l"]["i"].flattenedText }.filter { !$0.isEmpty }.joined(separator: "；")
            guard !head.isEmpty, !meaning.isEmpty else { return nil }
            return EnglishEntry.Phrase(phrase: head, meaning: meaning)
        }

        let sentences: [EnglishEntry.Sentence] = root["blng_sents_part"]["sentence-pair"].array.prefix(4).compactMap { item in
            let en = (item["sentence-eng"].string ?? item["sentence"].string ?? "").strippingHTML
            let zh = (item["sentence-translation"].string ?? "").strippingHTML
            guard !en.isEmpty, !zh.isEmpty else { return nil }
            return EnglishEntry.Sentence(english: en, chinese: zh)
        }

        let web = webTranslations(root, query: query)

        let headword = w["return-phrase"]["l"]["i"].flattenedText
        let simple = root["simple"]["word"].array.first ?? JSONValue(nil)
        let uk = w["ukphone"].nonEmptyString ?? simple["ukphone"].nonEmptyString
        let us = w["usphone"].nonEmptyString ?? simple["usphone"].nonEmptyString

        guard !defs.isEmpty || !web.isEmpty else { return nil }
        return EnglishEntry(
            word: headword.isEmpty ? query : headword,
            ukPhone: uk, usPhone: us,
            examTypes: ec["exam_type"].stringArray,
            definitions: defs,
            wordForms: forms,
            phrases: phrases,
            sentences: sentences,
            webTranslations: defs.isEmpty ? web : []
        )
    }

    /// "v. 跑，奔跑" → (v., 跑，奔跑)
    static func splitPOS(_ text: String) -> EnglishEntry.Definition {
        let pattern = #"^((?:[a-z]+\.\s*(?:&|和|/)?\s*)+)\s*(.+)$"#
        if let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
           let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r1 = Range(m.range(at: 1), in: text), let r2 = Range(m.range(at: 2), in: text) {
            return .init(pos: text[r1].trimmingCharacters(in: .whitespaces), text: String(text[r2]))
        }
        return .init(pos: "", text: text)
    }

    static func webTranslations(_ root: JSONValue, query: String) -> [String] {
        let items = root["web_trans"]["web-translation"].array
        let match = items.first { $0["key"].string?.lowercased() == query.lowercased() } ?? items.first
        guard let match else { return [] }
        return Array(match["trans"].array.compactMap { $0["value"].nonEmptyString?.strippingHTML }.prefix(5))
    }

    // MARK: - 日 → 中

    static func lookupJapanese(_ word: String) async throws -> JapaneseEntry? {
        guard var entry = parseJapanese(try await fetch(word, le: "ja"), query: word) else { return nil }
        // 查询活用形（如「食べた」）时有道不返回 JLPT 等级，用原形再查一次补全
        if entry.headword != word, entry.examTypes.isEmpty,
           let lemma = try? await fetch(entry.headword, le: "ja") {
            entry.examTypes = lemma["newjc"]["exam_type"].stringArray
        }
        return entry
    }

    static func parseJapanese(_ root: JSONValue, query: String) -> JapaneseEntry? {
        let newjc = root["newjc"]
        let w = newjc["word"]
        let head = w["head"]
        let headword = head["hw"].nonEmptyString?.strippingHTML

        // 现代日汉词典（简明释义 + 词性缩写）
        let jcWords = root["jc"]["word"].array
        let matchingJC = jcWords.filter { item in
            let hw = headword ?? query
            let origin = item["origin"].nonEmptyString
            let phrase = item["return-phrase"]["l"]["i"].flattenedText.replacingOccurrences(of: "·", with: "")
            return origin == nil || origin == hw || phrase == hw
                || origin == query || phrase == query
                || origin?.range(of: "[a-zA-Z]", options: .regularExpression) != nil  // 外来语原词
        }
        var brief: [JapaneseEntry.BriefDefinition] = []
        var origin: String?
        var jcReading: String?
        for item in matchingJC.prefix(2) {
            if let o = item["origin"].nonEmptyString, o.range(of: "^[a-zA-Z .\\-']+$", options: .regularExpression) != nil {
                origin = o
            }
            if jcReading == nil {
                jcReading = item["return-phrase"]["l"]["i"].flattenedText.replacingOccurrences(of: "·", with: "")
            }
            for tr in item["trs"].array {
                let pos = tr["pos"].nonEmptyString ?? ""
                let meanings = tr["tr"].array.map { $0["l"]["i"].flattenedText.strippingHTML }.filter { !$0.isEmpty }
                if !meanings.isEmpty { brief.append(.init(pos: pos, meanings: meanings)) }
            }
        }

        // 新日汉大辞典（详细释义、日文释义、例句）
        var senses: [JapaneseEntry.Sense] = []
        for s in w["sense"].array {
            let cx = (s["cx"].nonEmptyString ?? "").strippingHTML
            var meanings: [JapaneseEntry.Meaning] = []
            for p in s["phrList"].array {
                let zh = (p["jmsy"].string ?? "").strippingHTML.trimmingCharacters(in: .whitespacesAndNewlines)
                let ja = (p["jmsyT"].string ?? "").strippingHTML.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !zh.isEmpty || !ja.isEmpty else { continue }
                let ljs = p["lj"].array.map { ($0.string ?? "").strippingHTML }
                let ljTs = p["ljT"].array.map { ($0.string ?? "").strippingHTML }
                var examples: [JapaneseEntry.Example] = []
                for (i, sentence) in ljs.enumerated() where !sentence.isEmpty && examples.count < 3 {
                    let t = i < ljTs.count ? ljTs[i] : ""
                    examples.append(.init(tokens: FuriganaService.tokens(for: sentence), translation: t))
                }
                meanings.append(.init(chinese: zh, japanese: ja, examples: examples))
            }
            if !meanings.isEmpty { senses.append(.init(category: cx, meanings: meanings)) }
        }

        guard headword != nil || !brief.isEmpty || !senses.isEmpty else { return nil }

        let hw = headword ?? matchingJC.first?["origin"].nonEmptyString ?? query
        var hira = head["pjm"].nonEmptyString
        if hira == nil, let r = jcReading, !r.isEmpty { hira = r }
        var kata = head["ppjm"].nonEmptyString
        // 片假名词条：有道的平假名转写（如「こんぴゅうたあ」）对学习没有帮助，不显示
        let isKatakanaWord = hw.unicodeScalars.allSatisfy { (0x30A0...0x30FF).contains($0.value) }
        if isKatakanaWord { hira = nil; kata = nil }
        if kata == hira { kata = nil }

        var tone = head["tone"].nonEmptyString
        if tone == nil, let p = matchingJC.first?["phonesup"].nonEmptyString { tone = p }
        if let t = tone, t.allSatisfy({ $0.isNumber && $0.isASCII }), let n = Int(t) {
            tone = circled(n)
        }

        return JapaneseEntry(
            headword: hw,
            hiragana: hira,
            katakana: kata,
            romaji: head["rs"].nonEmptyString?.replacingOccurrences(of: "/", with: ""),
            tone: tone,
            examTypes: newjc["exam_type"].stringArray,
            brief: brief,
            senses: senses,
            origin: origin,
            audioText: hw
        )
    }

    static func circled(_ n: Int) -> String {
        let table = ["⓪", "①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩"]
        return n >= 0 && n < table.count ? table[n] : "\(n)"
    }

    // MARK: - 中 → 英 / 日

    static func lookupChineseEnglish(_ word: String) async throws -> ChineseEnglishEntry? {
        parseChineseEnglish(try await fetch(word, le: "en"))
    }

    static func parseChineseEnglish(_ root: JSONValue) -> ChineseEnglishEntry? {
        let w = root["ce"]["word"].array.first ?? JSONValue(nil)
        var items: [ChineseEnglishEntry.Item] = []
        for tr in w["trs"].array {
            for t in tr["tr"].array {
                let l = t["l"]
                // 「i」由纯文本与可点击单词交替组成（如 What␣are␣you…?），先拼回原文，
                // 再按真正的分隔符（;）拆成多个译法
                let words = l["i"].flattenedText
                    .split(whereSeparator: { $0 == ";" || $0 == "；" })
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                let tran = (l["#tran"].string ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "；; "))
                let pos = l["pos"].nonEmptyString ?? ""
                if words.isEmpty && tran.isEmpty { continue }
                items.append(.init(pos: pos, words: words, explanation: tran))
            }
        }
        // 汉英大辞典作为补充
        if items.isEmpty {
            let w2 = root["ce_new"]["word"].array.first ?? JSONValue(nil)
            for tr in w2["trs"].array {
                for t in tr["tr"].array {
                    let text = t["l"]["i"].flattenedText.trimmingCharacters(in: CharacterSet(charactersIn: ":： "))
                    guard !text.isEmpty else { continue }
                    let words = text.split(whereSeparator: { $0 == ";" || $0 == "；" })
                        .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    items.append(.init(pos: "", words: words, explanation: ""))
                }
            }
        }
        guard !items.isEmpty else { return nil }
        let pinyin = w["phone"].nonEmptyString ?? (root["ce_new"]["word"].array.first?["phone"].nonEmptyString)
        return ChineseEnglishEntry(pinyin: pinyin, items: items)
    }

    static func lookupChineseJapanese(_ word: String) async throws -> ChineseJapaneseEntry? {
        parseChineseJapanese(try await fetch(word, le: "ja"))
    }

    static func parseChineseJapanese(_ root: JSONValue) -> ChineseJapaneseEntry? {
        let w = root["cj"]["word"].array.first ?? JSONValue(nil)
        var words: [String] = []
        for tr in w["trs"].array {
            for t in tr["tr"].array {
                let text = t["l"]["i"].flattenedText.strippingHTML
                for part in text.split(whereSeparator: { "。；;，,、".contains($0) }) {
                    let p = part.trimmingCharacters(in: .whitespaces)
                    if !p.isEmpty, !words.contains(p) { words.append(p) }
                }
            }
        }
        let examples: [ChineseJapaneseEntry.Example] = root["newcj"]["ja_exam_sents"]["sents"].array.prefix(3).compactMap { s in
            let zh = (s["sent"].string ?? "").strippingHTML
            let ja = (s["sentTrans"].string ?? "").strippingHTML
            guard !zh.isEmpty, !ja.isEmpty else { return nil }
            return .init(chinese: zh, japaneseTokens: FuriganaService.tokens(for: ja))
        }
        guard !words.isEmpty || !examples.isEmpty else { return nil }
        return ChineseJapaneseEntry(pinyin: w["phone"].nonEmptyString, words: words, examples: examples)
    }

    // MARK: - 发音

    static func englishAudioURL(_ word: String, american: Bool) -> URL? {
        HTTP.url("https://dict.youdao.com/dictvoice", query: ["audio": word, "type": american ? "2" : "1"])
    }

    static func japaneseAudioURL(_ text: String) -> URL? {
        HTTP.url("https://dict.youdao.com/dictvoice", query: ["audio": text, "le": "jap"])
    }
}
