import Foundation
import SwiftUI

enum Loadable<T> {
    case idle
    case loading
    case loaded(T)
    case failed(String)

    var value: T? {
        if case .loaded(let v) = self { return v }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

/// 一次查询的完整状态。每个窗口（输入窗、划词卡片）持有一个实例。
@MainActor
final class LookupViewModel: ObservableObject {
    @Published var inputText: String = ""

    @Published private(set) var text: String = ""
    @Published private(set) var detectedLang: Lang = .zh
    @Published private(set) var sourceLang: Lang = .zh
    /// 用户手动指定的源语言；nil 表示由识别结果决定
    @Published private(set) var forcedSourceLang: Lang?
    @Published private(set) var isWord = false
    /// 纯汉字文本正在由识别服务判断中文 / 日语
    @Published private(set) var isDetecting = false
    @Published private(set) var sourceTokens: [RubyToken] = []

    // 辞典
    @Published private(set) var englishEntry: Loadable<EnglishEntry?> = .idle
    @Published private(set) var japaneseEntry: Loadable<JapaneseEntry?> = .idle
    @Published private(set) var chineseEnglish: Loadable<ChineseEnglishEntry?> = .idle
    @Published private(set) var chineseJapanese: Loadable<ChineseJapaneseEntry?> = .idle

    // 机器翻译
    @Published private(set) var translations: [Lang: Loadable<MachineTranslation>] = [:]
    @Published private(set) var translationTokens: [Lang: [RubyToken]] = [:]
    /// 英语单词 → 日语译词的简明词条；日语单词 → 英语译词的简明词条
    @Published private(set) var targetJapaneseEntry: JapaneseEntry?
    @Published private(set) var targetEnglishEntry: EnglishEntry?

    @Published private(set) var history: [(String, Lang?)] = []

    private var generation = 0
    private var tasks: [Task<Void, Never>] = []

    var hasQuery: Bool { !text.isEmpty }
    var canGoBack: Bool { !history.isEmpty }

    /// 纯汉字的词允许在「中文 / 日语」间手动切换（识别服务也可能判错）
    var canToggleChineseJapanese: Bool {
        !isDetecting && LanguageDetector.isAmbiguousChineseJapanese(text) && QueryClassifier.isWordLike(text, lang: .ja)
    }

    /// 纯汉字文本由识别服务判断中文 / 日语；forcedLang 为手动指定的源语言
    func lookup(_ raw: String, forcedLang: Lang? = nil, recordHistory: Bool = false) {
        let t = QueryClassifier.normalize(raw)
        if recordHistory, !text.isEmpty, t != text {
            history.append((text, forcedSourceLang))
        }
        cancel()
        generation += 1
        isDetecting = false
        let gen = generation

        text = t
        forcedSourceLang = forcedLang
        if inputText != raw { inputText = t }
        resetResults()
        guard !t.isEmpty else { return }

        detectedLang = LanguageDetector.detect(t)
        if forcedLang == nil, LanguageDetector.isAmbiguousChineseJapanese(t) {
            // 本地能判断的立即开始；否则先按中文占位显示加载中，在线检测出来后再正式查询
            if let lang = LanguageIdentifier.local(t) {
                detectedLang = lang
                start(t, lang: lang, gen: gen)
                return
            }
            sourceLang = .zh
            isWord = QueryClassifier.isWordLike(t, lang: .zh)
            isDetecting = true
            run { [weak self] in
                let lang = await LanguageIdentifier.online(t)
                guard let self, gen == self.generation else { return }
                self.isDetecting = false
                self.detectedLang = lang
                self.start(t, lang: lang, gen: gen)
            }
            return
        }
        start(t, lang: forcedLang ?? detectedLang, gen: gen)
    }

    private func start(_ t: String, lang: Lang, gen: Int) {
        sourceLang = lang
        isWord = QueryClassifier.isWordLike(t, lang: lang)
        sourceTokens = lang == .ja ? FuriganaService.tokens(for: t) : []

        for target in lang.others {
            translations[target] = .loading
            run { [weak self] in
                let r: Loadable<MachineTranslation>
                do { r = .loaded(try await MachineTranslator.translate(t, from: lang, to: target)) }
                catch { r = .failed(error.friendlyMessage) }
                self?.apply(gen) {
                    $0.translations[target] = r
                    if case .loaded(let mt) = r, target == .ja {
                        $0.translationTokens[.ja] = FuriganaService.tokens(for: mt.text)
                    }
                }
                if case .loaded(let mt) = r, self?.isWord == true {
                    await self?.lookupTargetEntry(mt.text, target: target, gen: gen)
                }
            }
        }

        guard isWord else { return }
        switch lang {
        case .en:
            englishEntry = .loading
            run { [weak self] in
                let r = await Self.load { try await YoudaoDictService.lookupEnglish(t) }
                self?.apply(gen) { $0.englishEntry = r }
            }
        case .ja:
            japaneseEntry = .loading
            run { [weak self] in
                let r = await Self.load { try await YoudaoDictService.lookupJapanese(t) }
                self?.apply(gen) { $0.japaneseEntry = r }
            }
        case .zh:
            chineseEnglish = .loading
            chineseJapanese = .loading
            run { [weak self] in
                let r = await Self.load { try await YoudaoDictService.lookupChineseEnglish(t) }
                self?.apply(gen) { $0.chineseEnglish = r }
            }
            run { [weak self] in
                let r = await Self.load { try await YoudaoDictService.lookupChineseJapanese(t) }
                self?.apply(gen) { $0.chineseJapanese = r }
            }
        }
    }

    func switchLanguage(_ lang: Lang) {
        guard lang != sourceLang, !text.isEmpty else { return }
        lookup(text, forcedLang: lang)
    }

    /// 点击释义中的单词跳转查询
    func follow(_ word: String) {
        lookup(word, recordHistory: true)
    }

    func goBack() {
        guard let (t, lang) = history.popLast() else { return }
        lookup(t, forcedLang: lang)
    }

    func retry() {
        lookup(text, forcedLang: forcedSourceLang)
    }

    func clear() {
        cancel()
        generation += 1
        isDetecting = false
        forcedSourceLang = nil
        text = ""
        inputText = ""
        history = []
        resetResults()
    }

    func cancel() {
        tasks.forEach { $0.cancel() }
        tasks = []
    }

    // MARK: - private

    private func resetResults() {
        sourceTokens = []
        englishEntry = .idle
        japaneseEntry = .idle
        chineseEnglish = .idle
        chineseJapanese = .idle
        translations = [:]
        translationTokens = [:]
        targetJapaneseEntry = nil
        targetEnglishEntry = nil
    }

    private func run(_ body: @escaping @MainActor () async -> Void) {
        tasks.append(Task { @MainActor in await body() })
    }

    private func apply(_ gen: Int, _ change: (LookupViewModel) -> Void) {
        guard gen == generation else { return }
        change(self)
    }

    private static func load<T>(_ op: () async throws -> T?) async -> Loadable<T?> {
        do { return .loaded(try await op()) }
        catch { return .failed(error.friendlyMessage) }
    }

    /// 单词查询时，为译出的日语/英语词补充简明词条（读音、词性等）
    private func lookupTargetEntry(_ word: String, target: Lang, gen: Int) async {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !w.isEmpty, QueryClassifier.isWordLike(w, lang: target) else { return }
        switch target {
        case .ja where sourceLang == .en:
            if let e = try? await YoudaoDictService.lookupJapanese(w) {
                apply(gen) { $0.targetJapaneseEntry = e }
            }
        case .en where sourceLang == .ja:
            // 只在词典词头与译文一致时显示，避免「i ate」被匹配成缩写「IATE」这类误配
            if let e = try? await YoudaoDictService.lookupEnglish(w),
               e.word.lowercased() == w.lowercased() {
                apply(gen) { $0.targetEnglishEntry = e }
            }
        default:
            break
        }
    }
}
