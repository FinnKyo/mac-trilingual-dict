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
        let e = try await YoudaoDictService.lookupJapanese("食べた")
        let entry = try XCTUnwrap(e)
        XCTAssertEqual(entry.headword, "食べる")
        XCTAssertEqual(entry.hiragana, "たべる")
        XCTAssertEqual(entry.tone, "②")
        XCTAssertTrue(entry.brief.contains { $0.pos.contains("他下一") })
        XCTAssertTrue(entry.senses.contains { $0.category.contains("他动词") })
        XCTAssertTrue(entry.examTypes.contains("N5"))
    }

    func testJapaneseKatakana() async throws {
        let entry_ = try await YoudaoDictService.lookupJapanese("コンピューター")
        let entry = try XCTUnwrap(entry_)
        XCTAssertNil(entry.hiragana)
        XCTAssertEqual(entry.origin, "computer")
        XCTAssertFalse(entry.brief.isEmpty)
    }

    func testJapaneseHomophonesFiltered() async throws {
        let entry_ = try await YoudaoDictService.lookupJapanese("今日")
        let entry = try XCTUnwrap(entry_)
        XCTAssertEqual(entry.hiragana, "きょう")
        // 「境」「興」等同音词不应混入
        XCTAssertEqual(entry.brief.count, 1)
    }

    func testChineseWord() async throws {
        let en_ = try await YoudaoDictService.lookupChineseEnglish("学习")
        let en = try XCTUnwrap(en_)
        XCTAssertTrue(en.items.flatMap(\.words).contains("learn"))
        let ja_ = try await YoudaoDictService.lookupChineseJapanese("学习")
        let ja = try XCTUnwrap(ja_)
        XCTAssertTrue(ja.words.contains("学習する"))
        XCTAssertFalse(ja.examples.isEmpty)
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

    func testLocalChineseJapaneseRecognition() {
        XCTAssertEqual(LanguageIdentifier.local("経済"), .ja)
        XCTAssertEqual(LanguageIdentifier.local("勉强"), .zh)
        // 中日通用的词本地拿不准，交给在线服务
        XCTAssertNil(LanguageIdentifier.local("大丈夫"))
        XCTAssertTrue(LanguageDetector.isKanjiOnly("影響"))
        XCTAssertFalse(LanguageDetector.isKanjiOnly("食べる"))
        XCTAssertFalse(LanguageDetector.isKanjiOnly("iPhone手机"))
    }

    @MainActor
    func testKanjiOnlyUsesDetectedLanguage() async throws {
        let vm = LookupViewModel()
        func settle() async {
            for _ in 0..<100 where vm.isDetecting { try? await Task.sleep(nanoseconds: 100_000_000) }
        }
        vm.lookup("経済")
        await settle()
        XCTAssertEqual(vm.sourceLang, .ja)
        vm.lookup("勉强")
        await settle()
        XCTAssertEqual(vm.sourceLang, .zh)
        // 手动指定优先于识别结果
        vm.lookup("経済", forcedLang: .zh)
        XCTAssertEqual(vm.sourceLang, .zh)
        vm.cancel()
    }

    func testAudioURLs() async throws {
        for url in [YoudaoDictService.englishAudioURL("run", american: true)!,
                    YoudaoDictService.japaneseAudioURL("食べる")!] {
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
