import Foundation

/// 有道词典网页版 jsonapi：英汉、汉英词典与发音；日语的收录情况只用于中日语言识别（日语词条见 MojiDictService）
enum YoudaoDictService {
    /// le: "en" 英汉/汉英, "ja" 日汉/汉日（只用于语言识别的收录判断）
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

    // MARK: - 中 → 英

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

    // MARK: - 发音

    static func englishAudioURL(_ word: String, american: Bool) -> URL? {
        HTTP.url("https://dict.youdao.com/dictvoice", query: ["audio": word, "type": american ? "2" : "1"])
    }
}
