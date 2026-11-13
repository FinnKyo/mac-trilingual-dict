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

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

/// 一次查询的完整状态（输入翻译窗持有一个实例）
@MainActor
final class LookupViewModel: ObservableObject {
    @Published var inputText: String = ""

    @Published private(set) var text: String = ""
    @Published private(set) var sourceLang: Lang = .zh
    /// 用户手动指定的源语言；nil 表示由识别结果决定
    @Published private(set) var forcedSourceLang: Lang?
    /// 指定显示的 MOJi 词条（同形异读词里点了其他读音）；nil 表示自动选择
    private(set) var preferredEntryId: String?
    @Published private(set) var isWord = false
    /// 纯汉字文本正在由识别服务判断中文 / 日语
    @Published private(set) var isDetecting = false
    @Published private(set) var sourceTokens: [RubyToken] = []

    // 辞典
    @Published private(set) var englishEntry: Loadable<EnglishEntry?> = .idle
    @Published private(set) var japaneseEntry: Loadable<JapaneseEntry?> = .idle
    /// 日语单词的国语辞典释义（大辞泉），在日语词条查到之后再查
    @Published private(set) var japaneseKokugo: Loadable<KokugoEntry?> = .idle
    @Published private(set) var chineseEnglish: Loadable<ChineseEnglishEntry?> = .idle
    @Published private(set) var chineseJapanese: Loadable<ChineseJapaneseEntry?> = .idle

    // 机器翻译
    @Published private(set) var translations: [Lang: Loadable<MachineTranslation>] = [:]
    @Published private(set) var translationTokens: [Lang: [RubyToken]] = [:]

    struct HistoryItem {
        var text: String
        var lang: Lang?
        var entryId: String?
    }
    @Published private(set) var history: [HistoryItem] = []

    private var generation = 0
    private var tasks: [Task<Void, Never>] = []
    /// 查询进行中被 cancel()（窗口关闭）打断，下次打开窗口时要重新查
    private var interrupted = false

    var hasQuery: Bool { !text.isEmpty }

    /// 有查询失败的部分（回车时据此重试）
    var hasFailures: Bool {
        englishEntry.isFailed || japaneseEntry.isFailed || japaneseKokugo.isFailed || chineseEnglish.isFailed || chineseJapanese.isFailed
            || translations.values.contains { $0.isFailed }
    }
    var canGoBack: Bool { !history.isEmpty }

    /// 中文单词的日语机器翻译照搬了字形、日语里意思却不同（床 → 床「地板」）时，那个日语同形词
    var japaneseFalseFriend: JapaneseCandidate? {
        guard sourceLang == .zh, isWord, let entry = chineseJapanese.value ?? nil,
              let mt = translations[.ja]?.value?.text else { return nil }
        return FalseFriendDetector.falseFriend(text, translation: mt, candidates: entry.candidates, equivalents: entry.equivalents)
    }

    /// 还有部分结果在加载中
    var isLoading: Bool {
        isDetecting || englishEntry.isLoading || japaneseEntry.isLoading || japaneseKokugo.isLoading
            || chineseEnglish.isLoading || chineseJapanese.isLoading || translations.values.contains { $0.isLoading }
    }

    /// 只有文字构成判断不了中日的汉字文本（命令、学习…）才允许手动切换；手动切换过的可以再切回来。
    /// 含「们 东 吃」或「経 駅」这类只有一边用的字时不会判错，不提供切换
    var canToggleChineseJapanese: Bool {
        guard !isDetecting, sourceLang != .en, LanguageDetector.isChineseOrJapaneseCandidate(text) else { return false }
        return forcedSourceLang != nil || LanguageDetector.analyze(text) == .ambiguous
    }

    /// 纯汉字文本由识别服务判断中文 / 日语；forcedLang 为手动指定的源语言，entryId 为指定的 MOJi 词条
    func lookup(_ raw: String, forcedLang: Lang? = nil, entryId: String? = nil, recordHistory: Bool = false) {
        let t = QueryClassifier.normalize(raw)
        if recordHistory, !text.isEmpty, t != text || entryId != preferredEntryId {
            history.append(HistoryItem(text: text, lang: forcedSourceLang, entryId: preferredEntryId))
        }
        cancel()
        interrupted = false
        isDetecting = false
        let gen = generation

        text = t
        forcedSourceLang = forcedLang
        preferredEntryId = entryId
        if inputText != raw { inputText = t }
        resetResults()
        guard !t.isEmpty else { return }

        if let forcedLang {
            start(t, lang: forcedLang, gen: gen)
            return
        }
        switch LanguageDetector.analyze(t) {
        case .certain(let lang):
            start(t, lang: lang, gen: gen)
        case .ambiguous:
            // 先按中文占位显示加载中，识别出来后再正式查询
            sourceLang = .zh
            isWord = QueryClassifier.isWordLike(t, lang: .zh)
            isDetecting = true
            run { [weak self] in
                let lang = await LanguageIdentifier.resolveAmbiguous(t).lang
                guard let self, gen == self.generation else { return }
                self.isDetecting = false
                self.start(t, lang: lang, gen: gen)
            }
        }
    }

    private func start(_ t: String, lang: Lang, gen: Int) {
        sourceLang = lang
        isWord = QueryClassifier.isWordLike(t, lang: lang)
        sourceTokens = lang == .ja ? FuriganaService.tokens(for: t) : []

        for target in lang.targets {
            translations[target] = .loading
            run { [weak self] in
                let r: Loadable<MachineTranslation>
                do { r = .loaded(try await MachineTranslator.translate(t, from: lang, to: target)) }
                catch { r = .failed(error.friendlyMessage) }
                guard let self, gen == self.generation else { return }
                self.translations[target] = r
                if case .loaded(let mt) = r {
                    if target == .ja { self.translationTokens[.ja] = FuriganaService.tokens(for: mt.text) }
                }
            }
        }

        guard isWord else { return }
        switch lang {
        case .en:
            load(\.englishEntry, gen: gen) { try await YoudaoDictService.lookupEnglish(t) }
        case .ja:
            let entryId = preferredEntryId
            load(\.japaneseEntry, gen: gen, { try await MojiDictService.lookup(t, preferredId: entryId) }) { vm, r in
                // 国语辞典按词条的原形和读音查；MOJi 没有这个词时用原文再试一次
                switch r {
                case .loaded(let entry?):
                    vm.load(\.japaneseKokugo, gen: gen) { try await WeblioService.daijisen(entry.headword, reading: entry.reading) }
                case .loaded(nil): vm.load(\.japaneseKokugo, gen: gen) { try await WeblioService.daijisen(t) }
                default: break
                }
            }
        case .zh:
            load(\.chineseEnglish, gen: gen) { try await YoudaoDictService.lookupChineseEnglish(t) }
            load(\.chineseJapanese, gen: gen) { try await MojiDictService.chineseToJapanese(t) }
        }
    }

    func switchLanguage(_ lang: Lang) {
        guard lang != sourceLang, !text.isEmpty else { return }
        lookup(text, forcedLang: lang)
    }

    /// 点击释义中的单词跳转查询；lang 指定时不再识别语言（如点击日语词条，避免「学校」被当成中文）；
    /// entryId 指定同形异读词中的某一条
    func follow(_ word: String, as lang: Lang? = nil, entryId: String? = nil) {
        lookup(word, forcedLang: lang, entryId: entryId, recordHistory: true)
    }

    func goBack() {
        guard let item = history.popLast() else { return }
        lookup(item.text, forcedLang: item.lang, entryId: item.entryId)
    }

    func retry() {
        lookup(text, forcedLang: forcedSourceLang, entryId: preferredEntryId)
    }

    /// 窗口关闭时打断了查询：重新打开时接着查（取消的请求不会显示成错误）
    func resumeIfInterrupted() {
        guard interrupted, hasQuery else { return }
        retry()
    }

    func clear() {
        cancel()
        interrupted = false
        isDetecting = false
        forcedSourceLang = nil
        preferredEntryId = nil
        text = ""
        inputText = ""
        history = []
        resetResults()
    }

    /// 取消进行中的请求。同时让本次查询作废：被取消的请求会以错误（-999、CancellationError）返回，不能写进界面
    func cancel() {
        if isLoading { interrupted = true }
        tasks.forEach { $0.cancel() }
        tasks = []
        generation += 1
    }

    // MARK: - private

    private func resetResults() {
        sourceTokens = []
        englishEntry = .idle
        japaneseEntry = .idle
        japaneseKokugo = .idle
        chineseEnglish = .idle
        chineseJapanese = .idle
        translations = [:]
        translationTokens = [:]
    }

    private func run(_ body: @escaping @MainActor () async -> Void) {
        tasks.append(Task { @MainActor in await body() })
    }

    private func apply(_ gen: Int, _ change: (LookupViewModel) -> Void) {
        guard gen == generation else { return }
        change(self)
    }

    /// 查一项辞典结果写入对应属性（先显示加载中）；then 在结果写入后执行（仍属于本次查询时）
    private func load<T>(_ keyPath: ReferenceWritableKeyPath<LookupViewModel, Loadable<T?>>, gen: Int,
                         _ op: @escaping () async throws -> T?,
                         then: ((LookupViewModel, Loadable<T?>) -> Void)? = nil) {
        apply(gen) { $0[keyPath: keyPath] = .loading }
        run { [weak self] in
            let r: Loadable<T?>
            do { r = .loaded(try await op()) } catch { r = .failed(error.friendlyMessage) }
            self?.apply(gen) {
                $0[keyPath: keyPath] = r
                then?($0, r)
            }
        }
    }
}
