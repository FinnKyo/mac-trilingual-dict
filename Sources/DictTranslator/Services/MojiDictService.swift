import Foundation

/// MOJi 辞書（mojidict.com）网页版使用的接口：日语词条、中文反查日语、真人发音。
/// 搜索走 REST 接口；完整词条和发音走 Parse 云函数（匿名可用，REST 的词条接口未登录时只返回第一个义项）
enum MojiDictService {
    private static let parseURL = "https://api.mojidict.com/parse/functions/"
    private static let restURL = "https://api.mojidict.com/app/mojidict"
    private static let applicationId = "E62VyFVLMiW7kvbtVq3p"
    private static let appVersion = "4.6.0"

    static let wordType = 102
    static let exampleType = 103

    private static let deviceId: String = {
        let key = "mojiDeviceId"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()

    private static let searchCache = Cache<[JapaneseCandidate]>()
    private static let entryCache = Cache<JapaneseEntry>()
    private static let audioCache = Cache<URL>()

    // MARK: - 查词

    /// 查日语单词（支持活用形，如「食べた」→「食べる」）。搜索结果和查询不相关时返回 nil
    static func lookup(_ query: String) async throws -> JapaneseEntry? {
        let candidates = try await search(query)
        guard let best = bestMatch(for: query, in: candidates) else { return nil }
        var entry = try await fetchEntry(id: best.id)
        entry.related = Array(related(to: entry, from: candidates.filter { $0.id != best.id && $0.spell != entry.headword }).prefix(6))
        return entry
    }

    /// 搜索结果里按读音模糊匹配的词很多（やばい → 夜番、野蛮），只留同音词（读音相同）和同词干的词（食べる → 食べ物）
    static func related(to entry: JapaneseEntry, from candidates: [JapaneseCandidate]) -> [JapaneseCandidate] {
        let reading = (entry.reading ?? entry.headword).hiragana
        let stem = stemOf(entry.headword)
        return candidates.filter { c in
            if (c.reading ?? c.spell).hiragana == reading { return true }
            return !stem.isEmpty && c.spell.hasPrefix(stem)
        }
    }

    /// 搜索日语词条。输入中文时返回对应的日语词（「学习」→ 学習、習う、学ぶ…）
    static func search(_ text: String) async throws -> [JapaneseCandidate] {
        if let hit = searchCache[text] { return hit }
        guard let url = HTTP.url(restURL + "/api/v2/search/all", query: ["text": text, "types": String(wordType), "highlight": "false"]) else {
            throw TranslatorError.badResponse
        }
        var req = URLRequest(url: url)
        restHeaders.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        let candidates = try await HTTP.json(req)["word"]["list"].array.compactMap(parseCandidate)
        searchCache[text] = candidates
        return candidates
    }

    static func fetchEntry(id: String) async throws -> JapaneseEntry {
        if let hit = entryCache[id] { return hit }
        let result = try await callFunction("nlt-fetchManyLatestWords", [
            "itemsJson": [["objectId": id]],
            "skipAccessories": false,
        ])
        guard let item = result["result"].array.first, let entry = parseEntry(item) else { throw TranslatorError.empty }
        entryCache[id] = entry
        return entry
    }

    /// 真人发音的音频地址。type：单词 102，例句 103
    static func audioURL(id: String, type: Int) async throws -> URL {
        let key = "\(type)#\(id)"
        if let hit = audioCache[key] { return hit }
        let result = try await callFunction("fetchTts_v2", ["tarId": id, "tarType": type])
        guard result["code"].string == "200", let s = result["result"]["url"].nonEmptyString, let url = URL(string: s) else {
            throw TranslatorError.empty
        }
        audioCache[key] = url
        return url
    }

    // MARK: - 选择最相关的词条

    /// MOJi 的搜索总会返回一些结果（输入乱码也会），只采用和查询对得上的：
    /// 词头或读音完全一致，或查询是词条的活用形（词干相同、后面只多了假名）
    static func bestMatch(for query: String, in candidates: [JapaneseCandidate]) -> JapaneseCandidate? {
        let q = query.hiragana
        if let exact = candidates.prefix(5).first(where: { $0.spell.hiragana == q || $0.reading?.hiragana == q }) {
            return exact
        }
        guard let top = candidates.first else { return nil }
        for form in [top.spell, top.reading].compactMap({ $0?.hiragana }) {
            let stem = stemOf(form)
            guard !stem.isEmpty, q.hasPrefix(stem), q != stem else { continue }
            let rest = q.dropFirst(stem.count)
            if rest.unicodeScalars.allSatisfy(LanguageDetector.isKana) { return top }
        }
        return nil
    }

    /// 去掉词尾的送假名得到词干（食べる → 食べ，たべる → たべ，大丈夫 → 大丈夫）
    private static func stemOf(_ word: String) -> String {
        if word.unicodeScalars.contains(where: LanguageDetector.isCJKIdeograph) {
            var s = Substring(word)
            while let last = s.unicodeScalars.last, LanguageDetector.isKana(last), s.count > 1 { s = s.dropLast() }
            // 留下一个送假名（食べる → 食べ），避免「食」这类过短的词干误配
            let kept = word.prefix(s.count + 1)
            return kept.count < word.count ? String(kept) : String(s)
        }
        return word.count > 2 ? String(word.dropLast()) : ""
    }

    // MARK: - 解析

    /// 搜索结果的标题形如「食べる | たべる ② | N2·N5」；同音词、片假名词有时把写法放在后面：
    /// 「かける | 架ける」「こんぴゅーたー | コンピューター ③」
    static func parseCandidate(_ item: JSONValue) -> JapaneseCandidate? {
        guard let id = item["targetId"].nonEmptyString, let title = item["title"].nonEmptyString else { return nil }
        let parts = title.components(separatedBy: " | ").map { $0.trimmingCharacters(in: .whitespaces) }
        var spell = parts[0]
        var reading: String?
        var tone: String?
        if parts.count > 1 {
            var words: [String] = []
            for w in parts[1].split(separator: " ").map(String.init) {
                if w.unicodeScalars.allSatisfy(isCircledDigit) { tone = w } else { words.append(w) }
            }
            reading = words.isEmpty ? nil : words.joined(separator: " ")
        }
        // 前面是纯平假名、后面是汉字或片假名写法时，后面那个才是词头
        if let r = reading, isAll(spell, katakana: false),
           isAll(r, katakana: true) || r.unicodeScalars.contains(where: LanguageDetector.isCJKIdeograph) {
            reading = spell
            spell = r
        }
        let tags = parts.count > 2 ? parts[2].components(separatedBy: "·").filter { !$0.isEmpty } : []
        return JapaneseCandidate(id: id, spell: spell, reading: reading == spell ? nil : reading, tone: tone,
                                 tags: tags, excerpt: item["excerpt"].nonEmptyString ?? "")
    }

    static func parseEntry(_ item: JSONValue) -> JapaneseEntry? {
        let w = item["word"]
        guard let id = w["objectId"].nonEmptyString, let spell = w["spell"].nonEmptyString else { return nil }
        let pron = w["pron"].nonEmptyString
        let excerpt = w["excerpt"].nonEmptyString ?? ""

        // 「[他动·一段] 吃；生活」→ 词性
        var partOfSpeech = ""
        if excerpt.hasPrefix("["), let close = excerpt.firstIndex(of: "]") {
            partOfSpeech = String(excerpt[excerpt.index(after: excerpt.startIndex)..<close])
        }

        let examplesBySense = Dictionary(grouping: item["examples"].array.compactMap { e -> (String, JapaneseEntry.Example)? in
            guard let sid = e["subdetailsId"].nonEmptyString, let title = e["title"].nonEmptyString else { return nil }
            let tokens = e["notationTitle"].nonEmptyString.flatMap(rubyTokens(fromNotation:)) ?? FuriganaService.tokens(for: title)
            let audio = e["objectId"].nonEmptyString.map { PronunciationSource.moji(id: $0, type: exampleType, text: title) }
            return (sid, .init(tokens: tokens, translation: (e["trans"].string ?? "").strippingHTML, audio: audio))
        }, by: \.0).mapValues { $0.map(\.1) }

        let subdetails = item["subdetails"].array
        var origin: String?
        var senses: [JapaneseEntry.Sense] = []
        // lang = ja 的是日文释义（日文解释看国语辞典），不用
        for s in subdetails where s["lang"].string != "ja" {
            guard let sid = s["objectId"].nonEmptyString, let title = s["title"].nonEmptyString?.strippingHTML else { continue }
            var chinese = chineseGloss(title)
            if senses.isEmpty, let (o, rest) = splitOrigin(chinese) { origin = o; chinese = rest }
            senses.append(.init(chinese: chinese, examples: examplesBySense[sid] ?? []))
        }
        guard !senses.isEmpty || !excerpt.isEmpty else { return nil }

        // 片假名词条的平假名转写（如「こんぴゅーたー」）对学习没有帮助，不显示
        let reading: String? = (pron == spell || isAll(spell, katakana: true)) ? nil : pron
        return JapaneseEntry(
            id: id,
            headword: spell,
            reading: reading,
            tone: w["accent"].nonEmptyString,
            romaji: w["romaji"].nonEmptyString,
            examTypes: (w["tags"].string ?? "").components(separatedBy: "#").filter { !$0.isEmpty },
            partOfSpeech: partOfSpeech,
            senses: senses,
            origin: origin,
            audio: .moji(id: id, type: wordType, text: spell)
        )
    }

    /// 「挂上，悬挂（つるす。）」→「挂上，悬挂」：去掉末尾括号里的日文释义
    static func chineseGloss(_ title: String) -> String {
        guard title.hasSuffix("）") else { return title }
        var depth = 0
        var i = title.endIndex
        while i > title.startIndex {
            i = title.index(before: i)
            if title[i] == "）" { depth += 1 }
            if title[i] == "（" { depth -= 1; if depth == 0 { break } }
        }
        guard depth == 0, title[i] == "（" else { return title }
        let inner = title[title.index(after: i)..<title.index(before: title.endIndex)]
        // 只有含假名才算日文（「（幕等）」这类是中文说明）
        guard inner.unicodeScalars.contains(where: LanguageDetector.isKana) else { return title }
        return String(title[..<i]).trimmingCharacters(in: .whitespaces)
    }

    /// 外来语释义开头的原词：「computer（电子）计算机，电脑」→（computer, （电子）计算机，电脑）
    private static func splitOrigin(_ chinese: String) -> (String, String)? {
        guard let r = chinese.range(of: #"^[A-Za-z][A-Za-z .\-']*"#, options: .regularExpression) else { return nil }
        let origin = chinese[r].trimmingCharacters(in: .whitespaces)
        let rest = chinese[r.upperBound...].trimmingCharacters(in: .whitespaces)
        guard origin.count >= 2, !rest.isEmpty else { return nil }
        return (origin, rest)
    }

    /// MOJi 例句自带的注音（<ruby><rb>食べ</rb>…<rt hiragana="たべ">），比本地分词更准确
    static func rubyTokens(fromNotation html: String) -> [RubyToken]? {
        let pattern = #"<ruby[^>]*><rb>(.*?)</rb>.*?<rt[^>]*hiragana="([^"]*)"[^>]*>.*?</ruby>|<span[^>]*>(.*?)</span>"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
        let ns = html as NSString
        var tokens: [RubyToken] = []
        for m in re.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            if m.range(at: 1).location != NSNotFound {
                let surface = ns.substring(with: m.range(at: 1)).strippingHTML
                let reading = ns.substring(with: m.range(at: 2))
                tokens += reading.isEmpty ? [RubyToken(surface: surface, reading: nil)]
                                          : FuriganaService.splitOkurigana(surface: surface, reading: reading)
            } else if m.range(at: 3).location != NSNotFound {
                tokens.append(RubyToken(surface: ns.substring(with: m.range(at: 3)).strippingHTML, reading: nil))
            }
        }
        return tokens.isEmpty ? nil : FuriganaService.merge(tokens)
    }

    private static func isCircledDigit(_ s: Unicode.Scalar) -> Bool {
        (0x2460...0x2473).contains(s.value) || s.value == 0x24EA || (0x24F5...0x24FE).contains(s.value)
    }

    private static func isAll(_ s: String, katakana: Bool) -> Bool {
        let range: ClosedRange<UInt32> = katakana ? 0x30A0...0x30FF : 0x3040...0x309F
        return !s.isEmpty && s.unicodeScalars.allSatisfy { range.contains($0.value) || $0.value == 0x30FC }
    }

    // MARK: - 请求

    private static var restHeaders: [String: String] {
        [
            "User-Agent": HTTP.userAgent,
            "Origin": "https://www.mojidict.com",
            "Referer": "https://www.mojidict.com/",
            "X-MOJI-OS": "PCWeb",
            "X-MOJI-APP-VERSION": appVersion,
            "X-MOJI-DEVICE-ID": deviceId,
        ]
    }

    private static func callFunction(_ name: String, _ params: [String: Any]) async throws -> JSONValue {
        var body = params
        body["_ApplicationId"] = applicationId
        body["_ClientVersion"] = "js3.4.1"
        body["g_os"] = "PCWeb"
        body["g_ver"] = "v\(appVersion)"
        let req = try HTTP.postJSON(URL(string: parseURL + name)!, body: body, headers: ["Origin": "https://www.mojidict.com"])
        return try await HTTP.json(req)["result"]
    }
}
