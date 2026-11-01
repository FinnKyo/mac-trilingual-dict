import XCTest
@testable import DictTranslator

final class LanguageTests: XCTestCase {
    func testDetect() {
        XCTAssertEqual(LanguageDetector.detect("学习"), .zh)
        XCTAssertEqual(LanguageDetector.detect("食べた"), .ja)
        XCTAssertEqual(LanguageDetector.detect("コンピューター"), .ja)
        XCTAssertEqual(LanguageDetector.detect("hello world"), .en)
        XCTAssertEqual(LanguageDetector.detect("我的iPhone坏了"), .zh)
        XCTAssertEqual(LanguageDetector.detect("I love 北京 very much"), .en)
        // 长中文里提到几个假名，不应整段当成日语
        let zhWithKana = String(repeating: "这是一段很长的中文说明，", count: 12) + "日语里的「ありがとう」表示感谢。"
        XCTAssertEqual(LanguageDetector.detect(zhWithKana), .zh)
        XCTAssertEqual(LanguageDetector.detect("I love sushi, すし is great and I eat it every day"), .en)
    }

    func testScriptEvidence() {
        // 日语字库独有的字（日本新字体、繁体字）→ 日语，即使夹着字母
        XCTAssertEqual(LanguageDetector.analyze("経済"), .certain(.ja))
        XCTAssertEqual(LanguageDetector.analyze("影響"), .certain(.ja))
        XCTAssertEqual(LanguageDetector.analyze("一般社団法人全日本空手審判機構（JKJO）"), .certain(.ja))
        // 简体中文字库独有的字 → 中文
        XCTAssertEqual(LanguageDetector.analyze("勉强"), .certain(.zh))
        XCTAssertEqual(LanguageDetector.analyze("我们"), .certain(.zh))
        XCTAssertEqual(LanguageDetector.analyze("一般社团法人全日本空手审判机构（JKJO）"), .certain(.zh))
        // 全是通用字：真正的歧义
        XCTAssertEqual(LanguageDetector.analyze("学校"), .ambiguous)
        XCTAssertEqual(LanguageDetector.analyze("寿司"), .ambiguous)
        XCTAssertEqual(LanguageDetector.analyze("大丈夫"), .ambiguous)
        // 生僻简体字（不在 GB2312，但有对应繁体）算中文
        XCTAssertEqual(LanguageDetector.hanOrigin(of: "镕"), .chineseOnly)
        XCTAssertEqual(LanguageDetector.hanOrigin(of: "経"), .japaneseOnly)
        XCTAssertEqual(LanguageDetector.hanOrigin(of: "学"), .shared)
    }

    /// 文字构成给出的结论必须零错误；同时要能覆盖大部分词汇，剩下的才交给词典 / 统计
    func testScriptVerdictsAreNeverWrongOnCorpus() {
        for (expected, items) in [(Lang.ja, LanguageCorpus.japanese), (Lang.zh, LanguageCorpus.chinese)] {
            var decided = 0
            for t in items {
                if case .certain(let lang) = LanguageDetector.analyze(t) {
                    decided += 1
                    XCTAssertEqual(lang, expected, t)
                }
            }
            XCTAssertGreaterThan(Double(decided) / Double(items.count), 0.5, "\(expected)")
        }
    }

    func testMojiParsing() {
        XCTAssertEqual(MojiDictService.chineseGloss("挂上，悬挂；拉，挂（幕等）（つるす。）"), "挂上，悬挂；拉，挂（幕等）")
        XCTAssertEqual(MojiDictService.chineseGloss("computer（电子）计算机，电脑"), "computer（电子）计算机，电脑")
        let html = #"<ruby ><rb>ご飯</rb><rp>(</rp><rt roma="gohan" hiragana="ごはん"></rt><rp>)</rp></ruby><span class="moji-toolkit-org">を</span><ruby n5><rb>食べる</rb><rp>(</rp><rt hiragana="たべる"></rt><rp>)</rp></ruby><span>。</span>"#
        let tokens = MojiDictService.rubyTokens(fromNotation: html) ?? []
        XCTAssertEqual(tokens.map(\.surface).joined(), "ご飯を食べる。")
        XCTAssertTrue(tokens.contains { $0.surface == "飯" && $0.reading == "はん" })
        XCTAssertTrue(tokens.contains { $0.surface == "食" && $0.reading == "た" })
        let c = MojiDictService.parseCandidate(JSONValue(["targetId": "1", "title": "食べる | たべる ② | N2·N5", "excerpt": "[他动·一段] 吃"]))
        XCTAssertEqual(c?.spell, "食べる"); XCTAssertEqual(c?.reading, "たべる"); XCTAssertEqual(c?.tone, "②"); XCTAssertEqual(c?.tags, ["N2", "N5"])
        let k = MojiDictService.parseCandidate(JSONValue(["targetId": "2", "title": "こんぴゅーたー | コンピューター ③ | N4"]))
        XCTAssertEqual(k?.spell, "コンピューター"); XCTAssertEqual(k?.reading, "こんぴゅーたー")
        let h = MojiDictService.parseCandidate(JSONValue(["targetId": "3", "title": "かける | 架ける ②"]))
        XCTAssertEqual(h?.spell, "架ける"); XCTAssertEqual(h?.reading, "かける"); XCTAssertEqual(h?.tone, "②")
    }

    func testQueryEncoding() {
        // 「+」不编码的话，服务器会把 C++ 当成 "C  "
        XCTAssertEqual(HTTP.encodeQueryValue("C++ a&b"), "C%2B%2B%20a%26b")
        let url = HTTP.url("https://example.com/x", query: ["q": "a+b", "le": "en"])
        XCTAssertEqual(url?.absoluteString, "https://example.com/x?q=a%2Bb&le=en")
        XCTAssertEqual(YoudaoDictService.englishAudioURL("Tom & Jerry", american: true)?.absoluteString,
                       "https://dict.youdao.com/dictvoice?audio=Tom%20%26%20Jerry&type=2")
    }

    func testStrippingHTML() {
        XCTAssertEqual("<b>a</b> &lt;i&gt; &amp;lt;".strippingHTML, "a <i> &lt;")
    }

    func testWordLike() {
        XCTAssertTrue(QueryClassifier.isWordLike("run", lang: .en))
        XCTAssertTrue(QueryClassifier.isWordLike("give up", lang: .en))
        XCTAssertFalse(QueryClassifier.isWordLike("I want to give up this job.", lang: .en))
        XCTAssertTrue(QueryClassifier.isWordLike("食べる", lang: .ja))
        XCTAssertFalse(QueryClassifier.isWordLike("今日は名物料理を食べた。", lang: .ja))
        XCTAssertTrue(QueryClassifier.isWordLike("学习", lang: .zh))
        XCTAssertFalse(QueryClassifier.isWordLike("我今天很开心，明天去东京。", lang: .zh))
    }

    func testFurigana() {
        let t = FuriganaService.tokens(for: "食べる")
        XCTAssertEqual(t.first?.surface, "食")
        XCTAssertEqual(t.first?.reading, "た")
        XCTAssertEqual(t.map(\.surface).joined(), "食べる")
    }

    /// 「表層(读音)」拼起来，方便整句比较
    private func ruby(_ text: String) -> String {
        FuriganaService.tokens(for: text).map { $0.surface + ($0.reading.map { "(\($0))" } ?? "") }.joined()
    }

    func testFuriganaUsesMeCab() {
        XCTAssertTrue(JapaneseAnalyzer.isAvailable)
        XCTAssertEqual(ruby("今日は一日中雨でした。"), "今日(きょう)は一日中(いちにちじゅう)雨(あめ)でした。")
        XCTAssertEqual(ruby("学校に行った"), "学校(がっこう)に行(い)った")
        XCTAssertEqual(ruby("調査を行った"), "調査(ちょうさ)を行(おこな)った")
        XCTAssertEqual(ruby("日本語"), "日本語(にほんご)")
        XCTAssertEqual(ruby("雨が降りそうだ"), "雨(あめ)が降(ふ)りそうだ")
        XCTAssertEqual(ruby("電車を降りる"), "電車(でんしゃ)を降(お)りる")
        XCTAssertEqual(ruby("生ビール"), "生(なま)ビール")
        // 换行、空白原样保留
        XCTAssertEqual(FuriganaService.tokens(for: "雨\n  晴れ").map(\.surface).joined(), "雨\n  晴れ")
    }

    func testFuriganaLemma() {
        let t = FuriganaService.tokens(for: "東京に行った")
        let go = t.filter { $0.lemma == "行く" }
        XCTAssertEqual(go.map(\.surface).joined(), "行った")
        XCTAssertEqual(Set(go.map(\.word)).count, 1)
        XCTAssertNil(t.first { $0.surface == "に" }?.lemma)
    }

    func testCounterReadings() {
        XCTAssertEqual(ruby("一人"), "一人(ひとり)")
        XCTAssertEqual(ruby("二十歳"), "二十歳(はたち)")
        XCTAssertEqual(ruby("三日"), "三日(みっか)")
        XCTAssertEqual(ruby("四月一日"), "四月(しがつ)一日(ついたち)")
        XCTAssertEqual(ruby("一本、三本、六本、何本"), "一本(いっぽん)、三本(さんぼん)、六本(ろっぽん)、何本(なんぼん)")
        XCTAssertEqual(ruby("十回"), "十回(じゅっかい)")
        XCTAssertEqual(ruby("三百円"), "三百円(さんびゃくえん)")
        XCTAssertEqual(ruby("七時半"), "七時半(しちじはん)")
        XCTAssertEqual(ruby("百人中"), "百人(ひゃくにん)中(ちゅう)")
        // 阿拉伯数字：规则读音只注量词，音变时整体注音
        XCTAssertEqual(ruby("3人"), "3人(にん)")
        XCTAssertEqual(ruby("3日"), "3日(みっか)")
        XCTAssertEqual(JapaneseNumerals.reading(of: 8_600), "はっせんろっぴゃく")
        XCTAssertEqual(JapaneseNumerals.parseKanji("二〇二四"), 2024)
        XCTAssertEqual(JapaneseNumerals.parseKanji("三千五百万"), 35_000_000)
    }

    /// 1 兆以上的数字（以前会数组越界 / 整数溢出闪退）原样显示，不注音
    func testHugeNumbersDoNotCrash() {
        XCTAssertEqual(JapaneseNumerals.parseKanji("一二三四五六七八九〇一二三四五六七八九〇一"), JapaneseNumerals.maxValue)
        XCTAssertEqual(JapaneseNumerals.parseKanji("九千九百九十九億九千九百九十九万九千九百九十九"), 999_999_999_999)
        for text in ["一〇〇〇〇〇〇〇〇〇〇〇〇", "10000000000000円です", "99999999999999999999999人", "一二三四五六七八九〇一二三四五六七八九〇一"] {
            let tokens = FuriganaService.tokens(for: text)
            XCTAssertEqual(tokens.map(\.surface).joined(), text)
        }
        XCTAssertEqual(ruby("九千九百九十九億円"), "九千九百九十九億円(きゅうせんきゅうひゃくきゅうじゅうきゅうおくえん)")
    }

    func testSplitPOS() {
        let d = YoudaoDictService.splitPOS("v. 跑，奔跑")
        XCTAssertEqual(d.pos, "v.")
        XCTAssertEqual(d.text, "跑，奔跑")
        XCTAssertEqual(YoudaoDictService.splitPOS("【名】 （Run）人名").pos, "")
    }
}

final class BingChunkTests: XCTestCase {
    func testShortTextIsOneChunk() {
        let c = BingTranslateService.chunks(of: "a\n\nb")
        XCTAssertEqual(c.map(\.text), ["a\n\nb"])
    }

    func testLongTextSplitsWithinLimit() {
        let paragraph = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 30)   // 1350 字符
        let c = BingTranslateService.chunks(of: "Title\n" + paragraph, limit: 1000)
        XCTAssertGreaterThan(c.count, 1)
        XCTAssertTrue(c.allSatisfy { $0.text.count <= 1000 })
        // 同一段落切开的句子不加换行；拼回去与原文一致
        XCTAssertFalse(c[1].startsLine)
        let rebuilt = c.enumerated().map { ($0.offset > 0 && $0.element.startsLine ? "\n" : "") + $0.element.text }.joined()
        XCTAssertEqual(rebuilt, "Title\n" + paragraph)
    }

    func testOverlongSentenceIsHardCut() {
        let c = BingTranslateService.chunks(of: String(repeating: "あ", count: 2500), limit: 1000)
        XCTAssertEqual(c.map(\.text.count), [1000, 1000, 500])
    }
}

final class NetworkServiceTests: XCTestCase {
    func testEnglishWord() async throws {
        let e = try await YoudaoDictService.lookupEnglish("run")
        let entry = try XCTUnwrap(e)
        XCTAssertEqual(entry.word, "run")
        XCTAssertNotNil(entry.usPhone)
        XCTAssertNotNil(entry.ukPhone)
        XCTAssertTrue(entry.definitions.contains { $0.pos == "v." })
        XCTAssertTrue(entry.wordForms.contains { $0.value == "ran" })
        XCTAssertFalse(entry.phrases.isEmpty)
        XCTAssertFalse(entry.sentences.isEmpty)
    }

    func testJapaneseConjugated() async throws {
        let entry_ = try await MojiDictService.lookup("食べた")
        let entry = try XCTUnwrap(entry_)
        XCTAssertEqual(entry.headword, "食べる")
        XCTAssertEqual(entry.reading, "たべる")
        XCTAssertEqual(entry.tone, "②")
        XCTAssertTrue(entry.partOfSpeech.contains("他动"), entry.partOfSpeech)
        XCTAssertTrue(entry.examTypes.contains("N5"))
        XCTAssertGreaterThanOrEqual(entry.senses.count, 2)
        XCTAssertTrue(entry.senses.contains { $0.chinese.contains("吃") })
        let examples = entry.senses.flatMap(\.examples)
        XCTAssertGreaterThanOrEqual(examples.count, 5)
        XCTAssertTrue(examples.allSatisfy { !$0.translation.isEmpty && $0.audio != nil })
        // 例句用 MOJi 自带的注音
        XCTAssertTrue(examples.contains { $0.tokens.contains { $0.surface == "食" && $0.reading == "た" } })
    }

    func testJapaneseKatakana() async throws {
        let entry_ = try await MojiDictService.lookup("コンピューター")
        let entry = try XCTUnwrap(entry_)
        XCTAssertEqual(entry.headword, "コンピューター")
        XCTAssertNil(entry.reading)
        XCTAssertEqual(entry.origin, "computer")
        XCTAssertFalse(entry.senses.isEmpty)
    }

    func testJapaneseHomophonesAsRelated() async throws {
        let entry_ = try await MojiDictService.lookup("かける")
        let entry = try XCTUnwrap(entry_)
        XCTAssertEqual(entry.headword, "掛ける")
        XCTAssertGreaterThanOrEqual(entry.senses.count, 8)
        XCTAssertFalse(entry.related.isEmpty)
    }

    func testRelatedEntriesAreHomophonesOrSameStem() async throws {
        let entry_ = try await MojiDictService.lookup("やばい")
        let entry = try XCTUnwrap(entry_)
        XCTAssertFalse(entry.related.contains { $0.spell == "野蛮" || $0.spell == "夜番" }, entry.related.map(\.spell).description)
    }

    func testJapaneseUnknownWord() async throws {
        // MOJi 对乱码也会返回结果，不能把不相关的词条当成答案
        let entry = try await MojiDictService.lookup("asdfqwer")
        XCTAssertNil(entry)
    }

    func testMojiAudio() async throws {
        let entry_ = try await MojiDictService.lookup("食べる")
        let entry = try XCTUnwrap(entry_)
        guard case .moji(let id, let type, _) = entry.audio else { return XCTFail("应为 MOJi 真人发音") }
        let url = try await MojiDictService.audioURL(id: id, type: type)
        let (_, resp) = try await URLSession.shared.data(from: url)
        let http = try XCTUnwrap(resp as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)
        XCTAssertTrue(http.mimeType?.hasPrefix("audio") ?? false, http.mimeType ?? "")
    }

    func testDaijisen() async throws {
        let k_ = try await WeblioService.daijisen("掛ける")
        let k = try XCTUnwrap(k_)
        XCTAssertTrue(k.heading.contains("掛ける"), k.heading)
        XCTAssertGreaterThan(k.lines.count, 20)
        XCTAssertTrue(k.lines.contains { $0.hasPrefix("１ ") || $0.hasPrefix("1 ") })
        // 大辞泉不是页面上第一个辞典时，标题不能混进其他辞典的内容
        let yabai_ = try await WeblioService.daijisen("やばい")
        let yabai = try XCTUnwrap(yabai_)
        XCTAssertEqual(yabai.heading, "やば・い")
        XCTAssertFalse((yabai.heading + yabai.lines.joined()).contains("googletag"))
        XCTAssertTrue(yabai.lines.contains { $0.contains("危険") })
        for word in ["勉強", "気", "食べる", "大丈夫", "猫"] {
            let k_ = try await WeblioService.daijisen(word)
            let k = try XCTUnwrap(k_, word)
            XCTAssertLessThan(k.heading.count, 40, "\(word): \(k.heading)")
            XCTAssertFalse(k.heading.contains("\n"), word)
            XCTAssertFalse(k.lines.contains { $0.contains("googletag") || $0.contains("function") }, word)
        }
        let missing = try await WeblioService.daijisen("asdfqwerzxcv")
        XCTAssertNil(missing)
    }

    func testChineseWord() async throws {
        let en_ = try await YoudaoDictService.lookupChineseEnglish("学习")
        let en = try XCTUnwrap(en_)
        XCTAssertTrue(en.items.flatMap(\.words).contains("learn"))
        // 中文反查日语（MOJi）
        let ja = try await MojiDictService.search("学习")
        XCTAssertTrue(ja.prefix(5).contains { $0.spell == "学習" }, ja.map(\.spell).description)
    }

    func testChinesePhraseNotSplitIntoWords() async throws {
        let e = try await YoudaoDictService.lookupChineseEnglish("你说啥")
        let entry = try XCTUnwrap(e)
        XCTAssertEqual(entry.items.first?.words, ["What are you talking about?"])
    }

    @MainActor
    func testBing() async throws {
        let r = try await BingTranslateService.translate("我今天很开心。", from: .zh, to: .en)
        XCTAssertTrue(r.lowercased().contains("today"), r)
        let j = try await BingTranslateService.translate("I like apples.", from: .en, to: .ja)
        XCTAssertTrue(j.contains("りんご") || j.contains("リンゴ"), j)
    }

    @MainActor
    func testFallbackChain() async throws {
        let r = try await MachineTranslator.translate("今日は天気がいいです。", from: .ja, to: .zh)
        XCTAssertTrue(r.text.contains("天气"), "\(r.engineName): \(r.text)")
    }

    func testRecognizerScore() {
        // 系统识别明确判为日语时是强证据；判中文只是弱证据；拿不准为 0
        XCTAssertGreaterThan(LanguageIdentifier.recognizerScore("経済産業省の発表によると"), 0)
        XCTAssertLessThan(LanguageIdentifier.recognizerScore("这是一个简体中文的句子"), 0)
    }

    /// 中日通用字的词：靠词典收录、词表和识别器的证据合并
    @MainActor
    func testIdentifyAmbiguousWords() async {
        for (word, expected) in [("手机", Lang.zh), ("新冠疫情", .zh), ("微信", .zh),
                                 ("人工知能", .ja), ("熊本地震", .ja), ("立入禁止", .ja)] {
            let r = await LanguageIdentifier.identify(word)
            XCTAssertEqual(r.lang, expected, "\(word) \(r.trace)")
        }
    }

    @MainActor
    func testLookupUsesIdentifiedLanguage() async throws {
        let vm = LookupViewModel()
        func settle() async {
            for _ in 0..<100 where vm.isDetecting { try? await Task.sleep(nanoseconds: 100_000_000) }
        }
        // 文字构成能定论的立即生效
        vm.lookup("経済")
        XCTAssertEqual(vm.sourceLang, .ja)
        vm.lookup("勉强")
        XCTAssertEqual(vm.sourceLang, .zh)
        vm.lookup("一般社団法人全日本空手審判機構（JKJO）")
        XCTAssertEqual(vm.sourceLang, .ja)
        // 歧义的词需要等识别结果
        vm.lookup("手机")
        XCTAssertTrue(vm.isDetecting)
        await settle()
        XCTAssertEqual(vm.sourceLang, .zh)
        // 手动指定优先于识别结果
        vm.lookup("経済", forcedLang: .zh)
        XCTAssertEqual(vm.sourceLang, .zh)
        vm.cancel()
    }

    func testAudioURLs() async throws {
        for url in [YoudaoDictService.englishAudioURL("run", american: true)!,
                    YoudaoDictService.englishAudioURL("give up", american: false)!] {
            var req = URLRequest(url: url)
            req.setValue(HTTP.userAgent, forHTTPHeaderField: "User-Agent")
            let (_, resp) = try await URLSession.shared.data(for: req)
            let http = try XCTUnwrap(resp as? HTTPURLResponse)
            XCTAssertEqual(http.statusCode, 200, url.absoluteString)
            XCTAssertEqual(http.mimeType, "audio/mpeg", url.absoluteString)
        }
    }

    func testOCR() async throws {
        // 渲染一段日文到图片，再识别
        let size = NSSize(width: 600, height: 120)
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor.white.setFill(); NSRect(origin: .zero, size: size).fill()
        ("今日は天気がいいです" as NSString).draw(at: NSPoint(x: 20, y: 40),
            withAttributes: [.font: NSFont.systemFont(ofSize: 40), .foregroundColor: NSColor.black])
        img.unlockFocus()
        let cg = try XCTUnwrap(img.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let text = try await OCRService.recognizeText(in: cg)
        XCTAssertTrue(text.contains("天気"), text)
    }
}

/// 同形异读词、取消查询的修复
final class HomographAndCancelTests: XCTestCase {
    func testOtherReadingsKeepSameSpellingOnly() {
        func c(_ id: String, _ spell: String, _ reading: String?) -> JapaneseCandidate {
            JapaneseCandidate(id: id, spell: spell, reading: reading, tone: nil, tags: [], excerpt: "")
        }
        let entry = JapaneseEntry(id: "0", headword: "生物", reading: "せいぶつ", tone: nil, romaji: nil, examTypes: [],
                                  partOfSpeech: "", senses: [], origin: nil, audio: .speech(text: "", language: "ja-JP"))
        let others = MojiDictService.otherReadings(of: entry, from: [
            c("1", "生物", "なまもの"), c("2", "生物", "いきもの"), c("3", "生物", "なまもの"),
            c("4", "生物", "セイブツ"), c("5", "生き物", "いきもの"), c("6", "生物", nil),
        ])
        XCTAssertEqual(others.map(\.id), ["1", "2"])
    }

    func testDaijisenPicksEntryByReading() {
        XCTAssertEqual(WeblioService.headingReading("なま‐もの【生物】"), "なまもの")
        XCTAssertEqual(WeblioService.headingReading("か・ける【掛ける／懸ける】"), "かける")
        let html = """
        <h2 class=midashigo title="生物">せい‐ぶつ【生物】</h2> <div class=Sgkdj><p>生命をもつもの。</p></div>
        <h2 class=midashigo title="生物">なま‐もの【生物】</h2> <div class=Sgkdj><p>煮たり焼いたりしていない食べ物。</p></div>
        """
        XCTAssertEqual(WeblioService.parseDaijisen(html, word: "生物", reading: "なまもの")?.lines, ["煮たり焼いたりしていない食べ物。"])
        XCTAssertEqual(WeblioService.parseDaijisen(html, word: "生物", reading: "せいぶつ")?.lines, ["生命をもつもの。"])
        // 没给读音、或读音对不上时取第一条
        XCTAssertEqual(WeblioService.parseDaijisen(html, word: "生物")?.lines, ["生命をもつもの。"])
        XCTAssertEqual(WeblioService.parseDaijisen(html, word: "生物", reading: "いきもの")?.lines, ["生命をもつもの。"])
    }

    /// 窗口关闭会取消查询：被取消的请求不能显示成「网络错误（-999）」，重新打开时接着查
    @MainActor
    func testCancelledLookupShowsNoErrorAndResumes() async {
        let vm = LookupViewModel()
        vm.lookup("食べる", forcedLang: .ja)
        XCTAssertTrue(vm.isLoading)
        vm.cancel()
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertFalse(vm.hasFailures, "\(vm.japaneseEntry) \(vm.translations)")
        vm.resumeIfInterrupted()
        XCTAssertTrue(vm.isLoading)
        for _ in 0..<100 where vm.isLoading { try? await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertEqual(vm.japaneseEntry.value??.headword, "食べる")
        // 已经查完的不会重查
        vm.cancel()
        vm.resumeIfInterrupted()
        XCTAssertFalse(vm.isLoading)
    }

    func testHomographEntries() async throws {
        let entry_ = try await MojiDictService.lookup("生物")
        let entry = try XCTUnwrap(entry_)
        let nama = try XCTUnwrap(entry.otherReadings.first { $0.reading == "なまもの" }, entry.otherReadings.description)
        XCTAssertFalse(entry.related.contains { $0.spell == "生物" })
        let picked_ = try await MojiDictService.lookup("生物", preferredId: nama.id)
        let picked = try XCTUnwrap(picked_)
        XCTAssertEqual(picked.reading, "なまもの")
        XCTAssertTrue(picked.otherReadings.contains { $0.reading == entry.reading })
        let k_ = try await WeblioService.daijisen("生物", reading: "なまもの")
        let k = try XCTUnwrap(k_)
        XCTAssertTrue(k.heading.hasPrefix("なま"), k.heading)
    }

    @MainActor
    func testFollowingOtherReadingKeepsHistory() async throws {
        let vm = LookupViewModel()
        func settle() async { for _ in 0..<100 where vm.isLoading { try? await Task.sleep(nanoseconds: 100_000_000) } }
        vm.lookup("生物", forcedLang: .ja)
        await settle()
        let first = try XCTUnwrap(vm.japaneseEntry.value ?? nil)
        let other = try XCTUnwrap(first.otherReadings.first)
        vm.follow(other.spell, as: .ja, entryId: other.id)
        await settle()
        XCTAssertEqual(vm.japaneseEntry.value??.id, other.id)
        XCTAssertTrue(vm.canGoBack)
        vm.goBack()
        await settle()
        XCTAssertEqual(vm.japaneseEntry.value??.id, first.id)
    }
}

final class AccuracyTests: XCTestCase {
    private func candidate(_ spell: String, _ reading: String?, _ excerpt: String) -> JapaneseCandidate {
        JapaneseCandidate(id: spell + (reading ?? ""), spell: spell, reading: reading, tone: nil, tags: [], excerpt: excerpt)
    }

    /// 机器翻译照搬字形、日语意思不同时报同形异义；同形同义（電話）、译文本身是对应词时不报
    func testFalseFriendDetection() {
        let yuka = candidate("床", "ゆか", "[名] 地板；地面")
        let bed = candidate("ベッド", "べっど", "[名] 床；床铺")
        XCTAssertEqual(FalseFriendDetector.falseFriend("床", translation: "床", candidates: [yuka, bed]), yuka)
        XCTAssertEqual(FalseFriendDetector.glossEquivalents("床", candidates: [yuka, bed]), [bed])
        XCTAssertNil(FalseFriendDetector.falseFriend("床", translation: "ベッド", candidates: [yuka, bed]))

        let kega = candidate("怪我", "けが", "[名·自他动·サ变] 受伤；负伤")
        XCTAssertEqual(FalseFriendDetector.falseFriend("怪我", translation: "けが", candidates: [kega]), kega)

        let hashiru = candidate("走る", "はしる", "[自动·五段] 跑；行驶")
        XCTAssertEqual(FalseFriendDetector.falseFriend("走", translation: "走る", candidates: [hashiru]), hashiru)

        let denwa = candidate("電話", "でんわ", "[名·サ变] 电话；打电话")
        XCTAssertNil(FalseFriendDetector.falseFriend("电话", translation: "電話", candidates: [denwa]))
        let yuumei = candidate("有名", "ゆうめい", "[形动] 著名；有名气")
        XCTAssertNil(FalseFriendDetector.falseFriend("有名", translation: "有名", candidates: [yuumei]))
        // 词典把同形词列为对应词（大丈夫 → 大丈夫）时相信词典
        let daijoubu = candidate("大丈夫", "だいじょうぶ", "[形动] 没关系；不要紧")
        XCTAssertNil(FalseFriendDetector.falseFriend("大丈夫", translation: "大丈夫", candidates: [daijoubu], equivalents: [daijoubu]))
        // 列表里的标签更保守：释义里出现了这个字就不标（床 とこ「床铺」）
        XCTAssertFalse(FalseFriendDetector.isClearlyDifferent(candidate("床", "とこ", "[名] 床铺；地面"), from: "床"))
        XCTAssertTrue(FalseFriendDetector.isClearlyDifferent(yuka, from: "床"))
    }

    func testYoudaoJapaneseTerms() {
        func tr(_ s: String) -> [String: Any] { ["tr": [["l": ["i": [s]]]]] }
        let root = JSONValue(["cj": ["word": [["trs": [tr("寝台。ベツド。"), tr("(助数詞)枚。"), tr("主人。夫(おつと)。")]]]]])
        XCTAssertEqual(YoudaoDictService.parseJapaneseTerms(root), ["寝台", "ベツド", "主人", "夫"])
    }

    /// 合并排版折行；分段、列表、标题、句末换行保留
    func testJoinSoftWraps() {
        XCTAssertEqual(QueryClassifier.joinSoftWraps("埃胡德·乌尔博士提醒，这项研究仍处在早期\n阶段，专家表示怀疑。"), "埃胡德·乌尔博士提醒，这项研究仍处在早期阶段，专家表示怀疑。")
        XCTAssertEqual(QueryClassifier.joinSoftWraps("The study is still at an early\nstage, and experts remain inter-\nnational skeptics."),
                       "The study is still at an early stage, and experts remain international skeptics.")
        XCTAssertEqual(QueryClassifier.joinSoftWraps("第一段的内容写在这里。\n\n第二段的内容写在这里。"), "第一段的内容写在这里。\n\n第二段的内容写在这里。")
        XCTAssertEqual(QueryClassifier.joinSoftWraps("需要准备的东西有这些\n・パスポート\n・航空券"), "需要准备的东西有这些\n・パスポート\n・航空券")
        XCTAssertEqual(QueryClassifier.joinSoftWraps("准备好以下材料\n1. 护照原件\n2. 机票行程单"), "准备好以下材料\n1. 护照原件\n2. 机票行程单")
        XCTAssertEqual(QueryClassifier.joinSoftWraps("目录\n第一章 总则和适用范围说明"), "目录\n第一章 总则和适用范围说明")
        XCTAssertEqual(QueryClassifier.joinSoftWraps("今日は晴れです。\n明日は雨が降るでしょう。"), "今日は晴れです。\n明日は雨が降るでしょう。")
        XCTAssertEqual(QueryClassifier.joinSoftWraps("自由民主党の内閣ではエド\n・デイビー下院議員が就任した"), "自由民主党の内閣ではエド・デイビー下院議員が就任した")
        XCTAssertEqual(QueryClassifier.joinSoftWraps("一行だけ"), "一行だけ")
    }
}
