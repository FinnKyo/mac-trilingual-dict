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
        XCTAssertEqual(MojiDictService.splitGloss("挂上，悬挂；拉，挂（幕等）（つるす。）").0, "挂上，悬挂；拉，挂（幕等）")
        XCTAssertEqual(MojiDictService.splitGloss("挂上，悬挂；拉，挂（幕等）（つるす。）").1, "つるす。")
        XCTAssertEqual(MojiDictService.splitGloss("computer（电子）计算机，电脑").1, "")
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

    func testSplitPOS() {
        let d = YoudaoDictService.splitPOS("v. 跑，奔跑")
        XCTAssertEqual(d.pos, "v.")
        XCTAssertEqual(d.text, "跑，奔跑")
        XCTAssertEqual(YoudaoDictService.splitPOS("【名】 （Run）人名").pos, "")
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
        XCTAssertTrue(entry.senses.contains { $0.chinese.contains("吃") && !$0.japanese.isEmpty })
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

    func testTencent() async throws {
        let r = try await TencentTranslateService.translate("我今天很开心。", from: .zh, to: .en)
        XCTAssertTrue(r.lowercased().contains("today"), r)
        let j = try await TencentTranslateService.translate("I like apples.", from: .en, to: .ja)
        XCTAssertTrue(j.contains("りんご") || j.contains("リンゴ"), j)
    }

    @MainActor
    func testFallbackChain() async throws {
        // Google 可能被限流，整条链路仍应返回结果
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
